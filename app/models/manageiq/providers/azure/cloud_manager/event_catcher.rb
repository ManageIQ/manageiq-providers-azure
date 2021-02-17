class ManageIQ::Providers::Azure::CloudManager::EventCatcher < ManageIQ::Providers::BaseManager::EventCatcher
  require_nested :Runner

  cache_with_timeout(:timeline_available, 1.hour) { Hash.new }

  def self.timeline_available?(ems)
    available = timeline_available[ems.id]
    return available unless available.nil?

    timeline_avaliable[ems.id] = ems.supports?(:timeline)
  end

  # Override the superclass method in order to disable event collection for
  # providers that do not support it.
  #
  def self.all_valid_ems_in_zone
    super.select do |ems|
      timeline_available?(ems).tap do |available|
        _log.info(ems.unsupported_reason(:timeline) + " [#{ems.provider_region}]") unless available
      end
    end
  end
end
