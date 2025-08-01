class ManageIQ::Providers::Azure::CloudManager::EventCatcher::Runner <
  ManageIQ::Providers::BaseManager::EventCatcher::Runner
  include ManageIQ::Providers::Azure::EventCatcherMixin

  def stop_event_monitor
    @event_monitor_handle.try(:stop)
  ensure
    reset_event_monitor_handle
  end

  def monitor_events
    event_monitor_handle.start
    event_monitor_running
    event_monitor_handle.each_batch do |events|
      _log.debug("#{log_prefix} Received events #{events.collect { |e| parse_event_type(e) }}")
      @queue.enq(events)
      sleep_poll_normal
    end
  ensure
    reset_event_monitor_handle
  end

  def process_event(event)
    if filtered?(event)
      _log.debug("#{log_prefix} Skipping filtered Azure event #{parse_event_type(event)} for #{event["resourceId"]}")
    else
      _log.info("#{log_prefix} Caught event #{parse_event_type(event)} for #{event["resourceId"]}")
      event_hash = ManageIQ::Providers::Azure::CloudManager::EventParser.event_to_hash(event, @cfg[:ems_id])
      EmsEvent.add_queue('add', @cfg[:ems_id], event_hash)
    end
  end

  private

  def event_monitor_handle
    @event_monitor_handle ||= ManageIQ::Providers::Azure::CloudManager::EventCatcher::Stream.new(@ems)
  end

  def reset_event_monitor_handle
    @event_monitor_handle = nil
  end

  def filtered?(event)
    event_type    = parse_event_type(event)
    provider_type = event["resourceProviderName"]["value"]

    @ems.blacklisted_provider_types.match(provider_type) || @ems.filtered_event_names.include?(event_type)
  end
end
