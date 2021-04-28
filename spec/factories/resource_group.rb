FactoryBot.define do
  factory :azure_resource_group,
          :parent => :resource_group,
          :class  => 'ManageIQ::Providers::Azure::CloudManager::ResourceGroup'
end
