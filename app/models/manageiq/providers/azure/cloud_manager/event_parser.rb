module ManageIQ::Providers::Azure::CloudManager::EventParser
  extend ManageIQ::Providers::Azure::EventCatcherMixin

  INSTANCE_TYPE = "microsoft.compute/virtualmachines".freeze

  # Convert the event to a hash that will ultimately be consumed by the
  # EmsEvent.add method.
  #
  # Note that we do not set the chain_id (i.e. group ID) because of a type
  # mismatch between Azure, which returns a GUID, and our schema, which is
  # set to bigint. For now it is not strictly necessary, and can be obtained
  # from the full_data column if necessary.
  #
  def self.event_to_hash(event, ems_id)
    log_header = "ems_id: [#{ems_id}] " unless ems_id.nil?
    event_type = parse_event_type(event)
    _log.debug("#{log_header}event: [#{event_type}]")

    # The timestamp must be truncated to 6 digit precision or a comparison
    # that happens within the EmsEvent model will fail, and duplicate events
    # could appear in the table.
    event_hash = {
      :source     => "AZURE",
      :timestamp  => Time.parse(event["eventTimestamp"]).iso8601(6),
      :message    => event["description"].presence || event.dig("operationName", "localizedValue").presence,
      :ems_id     => ems_id,
      :event_type => event_type,
      :full_data  => event,
      :ems_ref    => event["eventDataId"]
    }

    resource_type = event["resourceType"]["value"].to_s.downcase
    event_hash[:vm_uid_ems] = event_hash[:vm_ems_ref] = parse_vm_ref(event) if resource_type == INSTANCE_TYPE

    event_hash
  end
end
