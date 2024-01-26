class ManageIQ::Providers::Azure::CloudManager::EventCatcher < ManageIQ::Providers::BaseManager::EventCatcher
  # Override the superclass method in order to disable event collection for
  # providers that do not support it.
  #
  def self.all_valid_ems_in_zone
    super.select { |ems| ems.supports?(:events) }
  end
end
