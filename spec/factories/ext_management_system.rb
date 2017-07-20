FactoryGirl.define do
  factory :ems_azure_with_vcr_authentication, :parent => :ems_azure do
    zone do
      _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
      zone
    end

    after(:create) do |ems|
      client_id       = Rails.application.secrets.azure.try(:[], 'client_id') || 'AZURE_CLIENT_ID'
      client_key      = Rails.application.secrets.azure.try(:[], 'client_secret') || 'AZURE_CLIENT_SECRET'
      tenant_id       = Rails.application.secrets.azure.try(:[], 'tenant_id') || 'AZURE_TENANT_ID'
      subscription_id = Rails.application.secrets.azure.try(:[], 'subscription_id') || 'AZURE_SUBSCRIPTION_ID'

      cred = {
        :userid   => client_id,
        :password => client_key
      }

      ems.authentications << FactoryGirl.create(:authentication, cred)
      ems.update_attributes(:azure_tenant_id => tenant_id)
      ems.update_attributes(:subscription => subscription_id)
    end
  end
end
