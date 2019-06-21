# frozen_string_literal: true

## https://docs.microsoft.com/en-us/azure/azure-monitor/platform/metrics-supported#microsoftcomputevirtualmachines

class ManageIQ::Providers::Azure::CloudManager::MetricsCapture < ManageIQ::Providers::BaseManager::MetricsCapture
  INTERVAL_1_MINUTE = 'PT1M'
  VIM_INTERVAL = 20.seconds.freeze
  private_constant(*%i[INTERVAL_1_MINUTE VIM_INTERVAL])

  COUNTERS_INFO = [
    ## CPU
    {
      :counter_key => 'cpu_usage_rate_average',
      :source      => :api,
      :metrics     => [
        'Percentage CPU',
      ].freeze,
      :calculation => ->(stats) { stats.mean },
      :unit_key    => 'percent',
    },
    ## Memory
    {
      :counter_key => 'mem_usage_rate_average',
      :source      => :raw,
      :metrics     => [
        '/builtin/memory/percentusedmemory', # linux
        '\Memory\% Committed Bytes In Use', # windows
      ].freeze,
      :calculation => ->(stats) { stats.mean },
      :unit_key    => 'percent',
    },
    ## Disk
    {
      :counter_key => 'disk_usage_rate_average', # TODO: should be 'disk_usage_absolute_average',
      :source      => :api,
      :metrics     => [
        'Per Disk Read Bytes/sec',
        'Per Disk Write Bytes/sec',
      ].freeze,
      :calculation => ->(stats) { stats.sum / 1.kilobyte },
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
      :calculation => ->(stats) { stats.sum / 1.kilobyte },
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
    raise 'No EMS defined' unless ems

    unless ems.insights?
      _log.info("Metrics not supported for region: [#{provider_region}]")
      return
    end

    end_time   = end_time   ? end_time.utc   : Time.now.utc
    start_time = start_time ? start_time.utc : (end_time - 4.hours) # 4 hours for symmetry with VIM

    # This is just for consistency, to produce a :connect benchmark
    Benchmark.realtime_block(:connect) {}

    ems.with_provider_connection do |connection|
      metrics_conn = Azure::Armrest::Insights::MetricsService.new(connection)

      ## Counters from the metrics api

      metrics_uri = URI.join(
        metrics_conn.configuration.environment.resource_url,
        "#{resource_uri}/providers/microsoft.insights/metrics"
      )

      # https://docs.microsoft.com/en-us/rest/api/monitor/metrics/list#uri-parameters
      metrics_uri.query = URI.encode_www_form(
        'timespan'    => "#{start_time.iso8601}/#{end_time.iso8601}",
        'interval'    => INTERVAL_1_MINUTE,
        'metricnames' => api_metric_names.join(','),
        'aggregation' => 'Average',
        'api-version' => metrics_conn.api_version
      )

      metrics, _timings = Benchmark.realtime_block(:capture_counters) do
        # azure-armrest gem needs to be modified to accept query ('list_metrics' method)
        response = metrics_conn.send(:rest_get, metrics_uri.to_s)
        Azure::Armrest::ArmrestCollection.create_from_response(response, Azure::Armrest::Insights::Metric)
      end

      metrics = metrics.map do |metric|
        [metric.name.value, metric.timeseries.flat_map do |t|
          t.data.select { |d| d.respond_to?(:average) }
        end]
      end.to_h.freeze

      counter_values = api_counters_info.each_with_object({}) do |counter_info, memo|
        counter_metrics = metrics.values_at(*counter_info.metrics).compact.flatten

        # { timestamp => [value, ...], ... }
        timestamped_values = counter_metrics.each_with_object({}) do |metric_value, ts_memo|
          timestamp = Time.zone.parse(metric_value.time_stamp)
          (ts_memo[timestamp] ||= []) << metric_value.average
        end

        next if timestamped_values.empty?

        # { timestamp => value, ... }
        timestamped_values.transform_values! { |values| counter_info.calculation.call(values) }
        timestamped_values.sort_by! { |timestamp, _value| timestamp }

        timestamped_values.keys.each_cons(2) do |ts, next_ts|
          value = timestamped_values[ts]

          # For (temporary) symmetry with VIM API we create 20-second intervals.
          (ts...next_ts).step_value(VIM_INTERVAL).each do |inner_ts|
            memo.store_path(inner_ts.iso8601, counter_info.counter_key, value)
          end
        end

        # add last minute's value
        ts, value = timestamped_values.to_a.last
        memo.store_path(ts.iso8601, counter_info.counter_key, value)
      end

      # TODO: ## Counters, which available only through legacy API or storage account (raw)

      [{ ems_ref => VIM_STYLE_COUNTERS }, { ems_ref => counter_values }]
    end
  rescue ::Azure::Armrest::BadRequestException # Probably means region is not supported
    msg = "Problem collecting metrics for #{resource_description}. "\
          "Region [#{provider_region}] may not be supported."
    _log.warn(msg)
  rescue ::Azure::Armrest::RequestTimeoutException # Problem on Azure side
    _log.warn("Timeout attempting to collect metrics for: #{resource_description}. Skipping.")
  rescue ::Azure::Armrest::NotFoundException # VM deleted
    _log.warn("Could not find metrics for: #{resource_description}. Skipping.")
  rescue Exception => err
    log_header = "[#{interval_name}] for: [#{target.class.name}], [#{target.id}], [#{target.name}]"
    _log.error("#{log_header} Unhandled exception during perf data collection: [#{err}], class: [#{err.class}]")
    _log.error("#{log_header}   Timings at time of error: #{Benchmark.current_realtime.inspect}")
    _log.log_backtrace(err)
    raise
  end

  private

  def ems
    return @ems if defined? @ems

    @ems = target.ext_management_system
  end

  with_options :allow_nil => true do
    delegate :ems_ref,         :to => :target
    delegate :name,            :to => :target, :prefix => true
    delegate :provider_region, :to => :ems
  end

  alias resource_name target_name

  def resource_group
    return @resource_group if defined? @resource_group

    @resource_group = target.resource_group.name
  end

  def resource_description
    return @resource_description if defined? @resource_description

    @resource_description = "#{resource_name}/#{resource_group}"
  end

  def resource_uri
    return @resource_uri if defined? @resource_uri

    @resource_uri = [
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

  def api_counters_info
    COUNTERS_INFO[:api]
  end

  def api_metric_names
    METRIC_NAMES[:api]
  end

  def raw_counters_info
    COUNTERS_INFO[:raw]
  end

  def raw_metric_names
    METRIC_NAMES[:raw]
  end
end
