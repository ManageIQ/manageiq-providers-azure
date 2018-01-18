class ManageIQ::Providers::Azure::NetworkManager::CloudNetwork < ::CloudNetwork
  def self.display_name(number = 1)
    n_('Cloud Network (Microsoft Azure)', 'Cloud Networks (Microsoft Azure)', number)
  end
end
