class ManageIQ::Providers::Azure::CloudManager::EventCatcher::Stream
  #
  # Creates an event monitor
  #
  def initialize(ems)
    @ems = ems
    @collecting_events = false
    @since = nil
  end

  # Start capturing events
  def start
    @collecting_events = true
  end

  # Stop capturing events
  def stop
    @collecting_events = false
  end

  def each_batch
    while @collecting_events
      yield get_events.collect { |e| JSON.parse(e) }
    end
  end

  private

  # Get a list of events that have happened since the most recent event time.
  #
  # Because Azure event timestamps are not necessarily stamped in order, an
  # issue occurs where we could accidentally skip over events that happen
  # in quick succession. We must therefore begin our query a couple minutes
  # back from our most recent timestamp, and filter out any duplicates.
  #
  # See https://bugzilla.redhat.com/show_bug.cgi?id=1724312 for details.
  #
  def get_events
    filter = "eventTimestamp ge #{most_recent_time}"
    fields = 'authorization,description,eventDataId,eventName,eventTimestamp,resourceGroupName,resourceProviderName,resourceId,resourceType'

    events = connection.list(:filter => filter, :select => fields, :all => true)

    if events.present?
      existing_records = EventStream.select(:ems_ref).where(:source => 'AZURE', :ems_ref => events.map(&:event_data_id)).map(&:ems_ref)
      events = events.reject{ |e| existing_records.include?(e.event_data_id) } if existing_records.present?
    end

    events
  end

  # When the appliance first starts, or is restarted, start looking for events
  # from a fixed, recent point in the past.
  #
  def startup_interval
    format_timestamp(2.minutes.ago)
  end

  # Retrieve the most recent Azure event minus 2 minutes, or the startup interval
  # if no records are found. Go back a maximum of 1 hour if the newest record
  # is older than that.
  #
  def most_recent_time
    result = EventStream.select(:timestamp).where(:source => 'AZURE').order('timestamp desc').limit(1).first

    if result
      if result.timestamp < 1.hour.ago
        format_timestamp(1.hour.ago)
      else
        format_timestamp(result.timestamp - 2.minutes)
      end
    else
      startup_interval
    end
  end

  # Given a Time object, return a string suitable for the Azure REST API query.
  #
  def format_timestamp(time)
    time.strftime('%Y-%m-%dT%H:%M:%S.%L')
  end

  # A cached connection to the event service, which is used to query for events.
  #
  def connection
    @connection ||= create_event_service
  end

  # Create an event service object using the provider connection credentials.
  # This will be used by the +connection+ method to query for events.
  #
  def create_event_service
    @ems.with_provider_connection do |conf|
      Azure::Armrest::Insights::EventService.new(conf)
    end
  end
end
