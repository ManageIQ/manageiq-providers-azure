FactoryBot.define do
  factory :cloud_network_azure,
          :class  => "ManageIQ::Providers::Azure::NetworkManager::CloudNetwork",
          :parent => :cloud_network
end
