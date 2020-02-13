require 'azure-armrest'

describe ManageIQ::Providers::Azure::CloudManager::MetricsCapture do
  let(:ems)      { FactoryBot.create(:ems_azure) }
  let(:vm)       { FactoryBot.build(:vm_azure, :ext_management_system => ems, :ems_ref => "my_ems_ref") }
  let(:group)    { FactoryBot.build(:azure_resource_group) }
  let(:armrest_environment) { double('Armrest environment', :resource_url => 'http://example.com') }
  let(:armrest_service) { double('::Azure::Armrest::ArmrestService', :environment => armrest_environment) }

  before do
    allow(ems).to receive(:with_provider_connection).and_yield(armrest_service)
  end

  context "#perf_capture_object" do
    it "returns the correct class" do
      expect(vm.perf_capture_object.class).to eq(described_class)
    end
  end

  context "handles errors" do
    let(:metric) { described_class.new(self, ems) }

    before do
      allow(self).to receive(:ext_management_system).and_return(ems)
      allow(self).to receive(:name).and_return('target1')
      allow(self).to receive(:resource_group).and_return(group)
      allow(self).to receive(:id).and_return('1')
      allow(::Azure::Armrest::Insights::MetricsService).to receive(:new).and_return(armrest_service)
    end

    it "returns nothing if the insights service is not registered" do
      allow(ems).to receive(:insights?).and_return(false)
      counters, values = metric.perf_collect_metrics('whatever')
      expect(counters).to eq({})
      expect(values).to eq({})
    end

    it "returns nothing if the region is not supported" do
      allow(ems).to receive(:insights?).and_return(true)
      allow(armrest_service).to receive(:rest_get).and_raise(::Azure::Armrest::BadRequestException.new('x', 'y', 'z'))
      expect($log).to receive(:warn).with(/problem collecting metrics/i)
      counters, values = metric.perf_collect_metrics('whatever')
      expect(counters).to eq({})
      expect(values).to eq({})
    end

    it "returns nothing if a timeout occurs" do
      allow(ems).to receive(:insights?).and_return(true)
      allow(armrest_service).to receive(:rest_get).and_raise(::Azure::Armrest::RequestTimeoutException.new('x', 'y', 'z'))
      expect($log).to receive(:warn).with(/timeout attempting to collect metrics/i)
      counters, values = metric.perf_collect_metrics('whatever')
      expect(counters).to eq({})
      expect(values).to eq({})
    end

    it "returns nothing if the VM could not be found" do
      allow(ems).to receive(:insights?).and_return(true)
      allow(armrest_service).to receive(:rest_get).and_raise(::Azure::Armrest::NotFoundException.new('x', 'y', nil))
      expect($log).to receive(:warn).with(/could not find metrics for/i)
      counters, values = metric.perf_collect_metrics('whatever')
      expect(counters).to eq({})
      expect(values).to eq({})
    end

    it "raises an error if any other exception occurs" do
      allow(ems).to receive(:insights?).and_return(true)
      allow(armrest_service).to receive(:rest_get).and_raise(Exception.new)
      expect($log).to receive(:error).with(/unhandled exception/i)
      expect { metric.perf_collect_metrics('whatever') }.to raise_error(Exception)
    end
  end

  context "#perf_collect_metrics" do
    before do
      allow(ems).to receive(:insights?).and_return(true)
      allow(vm).to receive(:resource_group).and_return(group)
      allow(::Azure::Armrest::Insights::MetricsService).to receive(:new).and_return(armrest_service)
    end

    it "raises an error when no EMS is defined" do
      vm = FactoryBot.build(:vm_azure, :ext_management_system => nil)
      expect { vm.perf_collect_metrics('interval_name') }.to raise_error(RuntimeError, /No EMS defined/)
    end

    it "has definitions for cpu, memory, network and disk metrics" do
      # Don't stage any metrics
      counters    = []
      metric_data = []
      stage_metrics(metric_data, counters)

      counters_by_id, = vm.perf_collect_metrics('interval_name')

      expect(counters_by_id).to have_key("my_ems_ref")
      expect(counters_by_id["my_ems_ref"]).to have_key("cpu_usage_rate_average")
      expect(counters_by_id["my_ems_ref"]).to have_key("mem_usage_absolute_average")
      expect(counters_by_id["my_ems_ref"]).to have_key("disk_usage_rate_average")
      expect(counters_by_id["my_ems_ref"]).to have_key("net_usage_rate_average")
    end

    it "parses and handles cpu metrics" do
      counters = stage_counter_data(['Percentage CPU'])

      metric_data = [
        build_metric_data(0.788455, "2016-07-23T07:20:00.5580968Z"),
        build_metric_data(0.888455, "2016-07-23T07:21:00.5580968Z"),
        build_metric_data(0.988455, "2016-07-23T07:22:00.5580968Z")
      ]
      stage_metrics(metric_data, counters)

      _, metrics_by_id_and_ts = vm.perf_collect_metrics('interval_name')

      expected_metrics = {
        "my_ems_ref" => {
          "2016-07-23T07:20:00Z" => {
            "cpu_usage_rate_average" => 0.788455
          },
          "2016-07-23T07:20:20Z" => {
            "cpu_usage_rate_average" => 0.788455
          },
          "2016-07-23T07:20:40Z" => {
            "cpu_usage_rate_average" => 0.788455
          },
          "2016-07-23T07:21:00Z" => {
            "cpu_usage_rate_average" => 0.888455
          },
          "2016-07-23T07:21:20Z" => {
            "cpu_usage_rate_average" => 0.888455
          },
          "2016-07-23T07:21:40Z" => {
            "cpu_usage_rate_average" => 0.888455
          },
          "2016-07-23T07:22:00Z" => {
            "cpu_usage_rate_average" => 0.988455
          },
        }
      }
      expect(metrics_by_id_and_ts).to eq(expected_metrics)
    end

    it "parses and aggregates read and write on disk" do
      counters = stage_counter_data([
        'OS Disk Read Bytes/sec',
        'OS Disk Write Bytes/sec',
        'Data Disk Read Bytes/sec',
        'Data Disk Write Bytes/sec',
      ])

      metric_data = [
        build_metric_data(982_252_000, "2016-07-23T07:20:00.5580968Z"),
        build_metric_data(982_252_000, "2016-07-23T07:21:00.5580968Z"),
        build_metric_data(982_252_000, "2016-07-23T07:22:00.5580968Z")
      ]
      stage_metrics(metric_data, counters)

      _, metrics_by_id_and_ts = vm.perf_collect_metrics('interval_name')

      expected_metrics = {
        "my_ems_ref" => {
          "2016-07-23T07:20:00Z" => {
            "disk_usage_rate_average" => 1_918_460
          },
          "2016-07-23T07:20:20Z" => {
            "disk_usage_rate_average" => 1_918_460
          },
          "2016-07-23T07:20:40Z" => {
            "disk_usage_rate_average" => 1_918_460
          },
          "2016-07-23T07:21:00Z" => {
            "disk_usage_rate_average" => 1_918_460
          },
          "2016-07-23T07:21:20Z" => {
            "disk_usage_rate_average" => 1_918_460
          },
          "2016-07-23T07:21:40Z" => {
            "disk_usage_rate_average" => 1_918_460
          },
          "2016-07-23T07:22:00Z" => {
            "disk_usage_rate_average" => 1_918_460
          }
        }
      }
      expect(metrics_by_id_and_ts).to eq(expected_metrics)
    end
  end

  def stage_metrics(metric_data = nil, counters = nil)
    allow(ems).to receive(:connect).and_return(armrest_service)

    metrics_service     = double("Azure::Armrest::Insights::MetricsService")
    storage_acc_service = double(
      "Azure::Armrest::StorageAccountService",
      :name           => "defaultstorage",
      :resource_group => "Default-Storage"
    )
    allow_any_instance_of(described_class).to receive(:with_metrics_services)
      .and_yield(metrics_service, storage_acc_service)
    allow_any_instance_of(described_class).to receive(:storage_accounts) { [storage_acc_service] }
    allow(armrest_service).to receive(:rest_get) { counters }
    allow(::Azure::Armrest::ArmrestCollection).to receive(:create_from_response) { Array.wrap(counters) }
    allow(::Azure::Armrest::StorageAccountService).to receive(:new).and_return(storage_acc_service)
    allow(storage_acc_service).to receive(:list_account_keys) { { "key1"=>"key1" } }
    allow(storage_acc_service).to receive(:table_data) { metric_data }
    allow(storage_acc_service).to receive(:list_all) { metric_data }

    metric_data = OpenStruct.new(:data => metric_data)
    counters.each { |counter| allow(counter).to receive(:timeseries) { [metric_data] } }
  end

  def stage_counter_data(counters)
    metric_availabilities = []

    counters.each do |counter|
      azure_metric = Azure::Armrest::Insights::Metric.new(metric_hash(counter))
      metric_availabilities << azure_metric
    end
    metric_availabilities
  end

  def metric_hash(counter)
    {
      "name"                 => {
        "value" => counter,
      },
      "metricAvailabilities" => [
        {
          "timeGrain" => "PT1M",
          "location"  => {
            "tableEndpoint" => "https://defaultstorage.table.core.windows.net/",
            "tableInfo"     => [{ "tableName" => "table_name" }],
            "partitionKey"  => "key"
          }
        }
      ]
    }
  end

  def build_metric_data(consumption_value, timestamp)
    Azure::Armrest::StorageAccount::TableData.new(
      "average"    => consumption_value,
      "time_stamp" => timestamp
    )
  end
end
