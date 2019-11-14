class ManageIQ::Providers::Azure::NetworkManager::EventCatcher < ::MiqEventCatcher
  require_nested :Runner

  def self.settings_name
    :event_catcher_azure_network
  end
end
