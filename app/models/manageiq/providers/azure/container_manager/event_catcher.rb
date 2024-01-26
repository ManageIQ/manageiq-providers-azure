class ManageIQ::Providers::Azure::ContainerManager::EventCatcher < ManageIQ::Providers::BaseManager::EventCatcher
  def self.settings_name
    :event_catcher_azure_aks
  end
end
