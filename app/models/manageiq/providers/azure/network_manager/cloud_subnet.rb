class ManageIQ::Providers::Azure::NetworkManager::CloudSubnet < ::CloudSubnet
  def self.display_name(number = 1)
    n_('Cloud Subnet (Microsoft Azure)', 'Cloud Subnets (Microsoft Azure)', number)
  end
end
