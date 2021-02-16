# frozen_string_literal: true

## https://docs.microsoft.com/en-us/azure/azure-monitor/platform/metrics-supported#microsoftcomputevirtualmachines

class ManageIQ::Providers::Azure::CloudManager::MetricsCapture < ManageIQ::Providers::CloudManager::MetricsCapture
  INTERVAL_1_MINUTE = 'PT1M'
  VIM_INTERVAL = 20.seconds.freeze
  private_constant :INTERVAL_1_MINUTE, :VIM_INTERVAL

  COUNTERS_INFO = [
    ## CPU
    {
      :counter_key => 'cpu_usage_rate_average',
      :source      => :api,
      :metrics     => [
        'Percentage CPU',
      ].freeze,
      :calculation => ->(stats, _) { stats.mean },
      :unit_key    => 'percent',
    },
    ## Memory
    {
      :counter_key => 'mem_usage_absolute_average', # TODO: should be 'mem_usage_rate_average',
      :source      => :raw,
      :metrics     => [
        '/builtin/memory/percentusedmemory', # linux
        '\Memory\% Committed Bytes In Use', # windows
      ].freeze,
      :calculation => ->(stats, _) { stats.mean },
      :unit_key    => 'percent',
    },
    ## Disk
    {
      :counter_key => 'disk_usage_rate_average', # TODO: should be 'disk_usage_absolute_average',
      :source      => :api,
      :metrics     => [
        'Disk Read Bytes',
        'Disk Write Bytes',
      ].freeze,
      :calculation => ->(stats, interval) { stats.sum / 1.kilobyte / interval },
      :unit_key    => 'kilobytespersecond',
    },
    ## Network
    {
      :counter_key => 'net_usage_rate_average', # TODO: should be 'net_usage_absolute_average',
      :source      => :api,
      :metrics     => [
        'Network In Total',
        'Network Out Total',
      ].freeze,
      :calculation => ->(stats, interval) { stats.sum / 1.kilobyte / interval },
      :unit_key    => 'kilobytespersecond',
    },
  ].map { |h| OpenStruct.new(h).freeze }.group_by(&:source).to_h.freeze

  METRIC_NAMES = COUNTERS_INFO.map do |source, counters_info|
    [source, counters_info.flat_map(&:metrics).uniq]
  end.to_h.freeze

  VIM_STYLE_COUNTERS = COUNTERS_INFO.values.flatten.map do |counter_info|
    [counter_info.counter_key, {
      :counter_key           => counter_info.counter_key,
      :instance              => '',
      :capture_interval      => VIM_INTERVAL.to_s,
      :precision             => 1,
      :rollup                => 'average',
      :unit_key              => counter_info.unit_key,
      :capture_interval_name => 'realtime',
    }.freeze]
  end.to_h.freeze

  def perf_collect_metrics(interval_name, start_time = nil, end_time = nil)
    counters_by_mor = {}
    counter_values_by_mor = {}
    raise 'No EMS defined' unless ems

    unless ems.insights?
      _log.info("Metrics not supported for region: [#{provider_region}]")
      return counters_by_mor, counter_values_by_mor
    end

    end_time       = end_time   ? end_time.to_time.utc   : Time.now.utc
    start_time     = start_time ? start_time.to_time.utc : (end_time - 4.hours) # 4 hours for symmetry with VIM
    time_interval  = start_time..end_time
    data_interval  = 60.seconds
    counter_values = {}

    # This is just for consistency, to produce a :connect benchmark
    Benchmark.realtime_block(:connect) {}

    ems.with_provider_connection do |connection|
      base_url = connection.environment.resource_url

      ## Counters from the metrics api

      metrics_conn = Azure::Armrest::Insights::MetricsService.new(connection)

      metrics, _timings = Benchmark.realtime_block(:capture_counters) do
        # azure-armrest gem needs to be modified to accept query ('list_metrics' method)
        response = metrics_conn.send(:rest_get, metrics_url(base_url, start_time, end_time).to_s)
        Azure::Armrest::ArmrestCollection.create_from_response(response, Azure::Armrest::Insights::Metric)
      end

      # { metric_name => { timestamp => [value, ...], ... }, ... }
      metrics = metrics.map do |metric|
        metric_values = metric.timeseries.flat_map do |t|
          t.data.select { |d| d.respond_to?(:average) }
        end
        timestamped_values = metric_values.each_with_object({}) do |metric_value, memo|
          timestamp = parse_timestamp(metric_value.time_stamp)
          (memo[timestamp] ||= []) << metric_value.average
        end
        [metric.name.value, timestamped_values]
      end.to_h

      ## Counters, which are available only through legacy API and storage account (raw)

      storage_conn = Azure::Armrest::StorageAccountService.new(connection)
      storage_accounts = storage_conn.list_all

      metric_definitions, _timings = Benchmark.realtime_block(:capture_counters) do
        # azure-armrest gem needs to be modified to accept version ('list_definitions' method)
        response = metrics_conn.send(:rest_get, definitions_url(base_url).to_s)
        Azure::Armrest::ArmrestCollection.create_from_response(response, Azure::Armrest::Insights::MetricDefinition)
      end

      metric_definitions.each do |metric_definition|
        metric_name = metric_definition.name.value
        next unless METRIC_NAMES[:raw].include?(metric_name)

        metric_availability = metric_definition.metric_availabilities.detect { |ma| ma.time_grain == INTERVAL_1_MINUTE }
        next unless metric_availability

        timestamped_values = metrics[metric_name] ||= {}

        metric_location = metric_availability.location

        storage_account_name = URI.parse(metric_location.table_endpoint).host.split('.').first
        storage_account      = storage_accounts.find { |account| account.name == storage_account_name }
        storage_account_keys = storage_conn.list_account_keys(storage_account.name, storage_account.resource_group)
        storage_account_key  = storage_account_keys.fetch('key1')

        filter = <<~FILTER
          CounterName eq '#{metric_name}' and \
          PartitionKey eq '#{metric_location.partition_key}' and \
          Timestamp ge datetime'#{start_time.iso8601}' and \
          Timestamp le datetime'#{end_time.iso8601}'
        FILTER

        metric_location.table_info.each do |table_info|
          t_start_time = parse_timestamp(table_info.start_time)
          t_end_time   = parse_timestamp(table_info.end_time).end_of_day
          next unless time_interval.overlaps?(t_start_time..t_end_time)

          table_data, _timings = Benchmark.realtime_block(:capture_counters) do
            storage_account.table_data(
              table_info.table_name,
              storage_account_key,
              :filter => filter,
              :select => 'TIMESTAMP,Average',
              :all    => true
            )
          end

          table_data.each do |row_data|
            timestamp = parse_timestamp(row_data.timestamp)
            (timestamped_values[timestamp] ||= []) << row_data.average
          end
        end
      end

      ## Organize data in the proper form

      COUNTERS_INFO.values.flatten.each do |counter_info|
        metric_values = metrics.values_at(*counter_info.metrics).compact
        next if metric_values.empty?

        # { timestamp => [value, ...], ... }
        timestamped_values = Hash.new { |h, k| h[k] = [] }
        metric_values.each do |ts_values|
          ts_values.each do |timestamp, values|
            timestamped_values[timestamp].concat(values)
          end
        end

        # { timestamp => value, ... }
        timestamped_values.transform_values! do |values|
          counter_info.calculation.call(values, data_interval)
        end

        timestamped_values.sort_by! { |timestamp, _value| timestamp }
        timestamped_values.keys.each_cons(2) do |ts, next_ts|
          value = timestamped_values[ts]

          # For (temporary) symmetry with VIM API we create 20-second intervals.
          (ts...next_ts).step_value(VIM_INTERVAL).each do |inner_ts|
            counter_values.store_path(inner_ts.iso8601, counter_info.counter_key, value)
          end
        end

        # add last minute's value
        ts, value = timestamped_values.to_a.last
        counter_values.store_path(ts.iso8601, counter_info.counter_key, value) if ts
      end
    end

    counter_values.sort_by! { |timestamp, _value| timestamp }

    counters_by_mor[ems_ref]       = VIM_STYLE_COUNTERS
    counter_values_by_mor[ems_ref] = counter_values

    return counters_by_mor, counter_values_by_mor
  rescue ::Azure::Armrest::BadRequestException => err # Probably means region is not supported
    msg = "Problem collecting metrics for #{resource_description}: #{err}. "\
          "Region [#{provider_region}] may not be supported."
    _log.warn(msg)
    return counters_by_mor, counter_values_by_mor
  rescue ::Azure::Armrest::RequestTimeoutException # Problem on Azure side
    _log.warn("Timeout attempting to collect metrics for: #{resource_description}. Skipping.")
    return counters_by_mor, counter_values_by_mor
  rescue ::Azure::Armrest::NotFoundException # VM deleted
    _log.warn("Could not find metrics for: #{resource_description}. Skipping.")
    return counters_by_mor, counter_values_by_mor
  rescue Exception => err
    log_header = "[#{interval_name}] for: [#{target.class.name}], [#{target.id}], [#{target.name}]"
    _log.error("#{log_header} Unhandled exception during perf data collection: [#{err}], class: [#{err.class}]")
    _log.error("#{log_header}   Timings at time of error: #{Benchmark.current_realtime.inspect}")
    _log.log_backtrace(err)
    raise
  end

  private

  def ems
    defined?(@ems) ? @ems : @ems = target.ext_management_system
  end

  with_options :allow_nil => true do
    delegate :ems_ref,         :to => :target
    delegate :name,            :to => :target, :prefix => true
    delegate :provider_region, :to => :ems
  end

  alias resource_name target_name

  def resource_group
    @resource_group ||= target.resource_group.name.to_s
  end

  def resource_description
    @resource_description ||= "#{resource_name}/#{resource_group}"
  end

  def resource_uri
    @resource_uri ||= [
      'subscriptions',
      ems.subscription,
      'resourceGroups',
      resource_group,
      'providers',
      'Microsoft.Compute', # resourceProviderNamespace
      'virtualMachines',   # resourceType
      resource_name,
    ].join('/')
  end

  def resource_url(base_url, tail_path = nil, query = {})
    url       = URI.join(base_url, resource_uri)
    url.path  = [url.path, tail_path].join('/') if tail_path
    url.query = URI.encode_www_form(query) unless query.empty?
    url
  end

  def metrics_url(base_url, start_time, end_time)
    resource_url(
      base_url,
      'providers/microsoft.insights/metrics',
      # https://docs.microsoft.com/en-us/rest/api/monitor/metrics/list#uri-parameters
      'timespan'    => "#{start_time.iso8601}/#{end_time.iso8601}",
      'interval'    => INTERVAL_1_MINUTE,
      'metricnames' => METRIC_NAMES[:api].join(','),
      'aggregation' => 'Average',
      'api-version' => '2018-01-01'
    ).freeze
  end

  def definitions_url(base_url)
    resource_url(
      base_url,
      'providers/microsoft.insights/metricDefinitions',
      'api-version' => '2015-07-01'
    ).freeze
  end

  def parse_timestamp(timestamp)
    Time.parse(timestamp).utc
  end
end
