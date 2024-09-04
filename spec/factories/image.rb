FactoryBot.define do
  factory :azure_image, :class => 'ManageIQ::Providers::Azure::CloudManager::Template' do
    sequence(:name) { |n| "Azure Image #{n}" }
    location { "azure" }
    vendor { "azure" }
  end
end
