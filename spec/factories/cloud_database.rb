FactoryBot.define do
  factory :cloud_database_azure,
          :class => "ManageIQ::Providers::Azure::CloudManager::CloudDatabase"
end
