class ManageIQ::Providers::Azure::CloudManager::EventCatcher < ManageIQ::Providers::BaseManager::EventCatcher
  require_nested :Runner

  # Override the superclass method in order to disable event collection for
  # providers that do not support it.
  #
  def self.all_valid_ems_in_zone
    super.select do |ems|
      ems.supports_timeline?.tap do |available|
        _log.info(ems.unsupported_reason(:timeline) + " [#{ems.provider_region}]") unless available
      end
    end
  end
end
