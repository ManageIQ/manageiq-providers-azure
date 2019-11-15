class ManageIQ::Providers::Azure::NetworkManager::RefreshWorker < ::MiqEmsRefreshWorker
  require_nested :Runner

  def self.settings_name
    :ems_refresh_worker_azure_network
  end
end
