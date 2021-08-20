class ManageIQ::Providers::Azure::ContainerManager::RefreshWorker < ManageIQ::Providers::BaseManager::RefreshWorker
  require_nested :Runner
  require_nested :WatchThread

  def self.settings_name
    :ems_refresh_worker_azure_aks
  end
end
