FactoryBot.define do
  factory :ems_azure_with_vcr_authentication, :parent => :ems_azure do
    zone do
      _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
      zone
    end

    after(:create) do |ems|
      client_id       = Rails.application.secrets.azure[:client_id]
      client_key      = Rails.application.secrets.azure[:client_secret]
      tenant_id       = Rails.application.secrets.azure[:tenant_id]
      subscription_id = Rails.application.secrets.azure[:subscription_id]

      cred = {
        :userid   => client_id,
        :password => client_key
      }

      ems.authentications << FactoryBot.create(:authentication, cred)
      ems.update(:azure_tenant_id => tenant_id)
      ems.update(:subscription => subscription_id)
    end
  end

  factory :ems_azure_aks,
          :aliases => ["manageiq/providers/azure/container_manager"],
          :class   => "ManageIQ::Providers::Azure::ContainerManager",
          :parent  => :ems_container do
    provider_region { "eastus" }
    security_protocol { "ssl-without-validation" }
    port { 443 }
  end
end
