class ManageIQ::Providers::Azure::NetworkManager::NetworkPort < ::NetworkPort
  def self.display_name(number = 1)
    n_('Network Port (Microsoft Azure)', 'Network Ports (Microsoft Azure)', number)
  end
end
