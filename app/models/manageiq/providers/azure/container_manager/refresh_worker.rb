class ManageIQ::Providers::Azure::ContainerManager::RefreshWorker < ManageIQ::Providers::BaseManager::RefreshWorker
  def self.settings_name
    :ems_refresh_worker_azure_aks
  end
end
