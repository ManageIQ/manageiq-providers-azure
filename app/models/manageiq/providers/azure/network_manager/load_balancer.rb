class ManageIQ::Providers::Azure::NetworkManager::LoadBalancer < ::LoadBalancer
  def self.display_name(number = 1)
    n_('Load Balancer (Microsoft Azure)', 'Load Balancers (Microsoft Azure)', number)
  end
end
