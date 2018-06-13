class ManageIQ::Providers::Azure::CloudManager::Flavor < ::Flavor
  def self.display_name(number = 1)
    n_('Flavor (Microsoft Azure)', 'Flavors (Microsoft Azure)', number)
  end
end
