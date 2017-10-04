module ManageIQ::Providers::Azure::ManagerMixin
  extend ActiveSupport::Concern

  def connect(options = {})
    raise MiqException::MiqHostError, _("No credentials defined") if missing_credentials?(options[:auth_type])

    client_id  = options[:user] || authentication_userid(options[:auth_type])
    client_key = options[:pass] || authentication_password(options[:auth_type])
    self.class.raw_connect(client_id, client_key, azure_tenant_id, subscription, options[:proxy_uri] || http_proxy_uri, provider_region)
  end

  def verify_credentials(_auth_type = nil, options = {})
    require 'azure-armrest'
    conf = connect(options)
  rescue ArgumentError => err
    raise MiqException::MiqInvalidCredentialsError, _("Incorrect credentials - #{err.message}")
  rescue ::Azure::Armrest::UnauthorizedException, ::Azure::Armrest::BadRequestException
    raise MiqException::MiqInvalidCredentialsError, _("Incorrect credentials - check your Azure Client ID and Client Key")
  rescue MiqException::MiqInvalidCredentialsError
    raise # Raise before falling into catch-all block below
  rescue => err
    _log.error("Error Class=#{err.class.name}, Message=#{err.message}, Backtrace=#{err.backtrace}")
    raise MiqException::MiqInvalidCredentialsError, _("Unexpected response returned from system: #{err.message}")
  else
    conf
  end

  module ClassMethods
    def raw_connect(client_id, client_key, azure_tenant_id, subscription, proxy_uri = nil, provider_region = nil)

      require 'azure-armrest'

      if subscription.blank?
        raise MiqException::MiqInvalidCredentialsError, _("Incorrect credentials - check your Azure Subscription ID")
      end

      ::Azure::Armrest::Configuration.log = $azure_log

      ::Azure::Armrest::Configuration.new(
        :client_id       => client_id,
        :client_key      => MiqPassword.try_decrypt(client_key),
        :tenant_id       => azure_tenant_id,
        :subscription_id => subscription,
        :proxy           => proxy_uri,
        :environment     => environment_for(provider_region)
      )
    end

    def environment_for(region)
      case region
      when /germany/i
        ::Azure::Armrest::Environment::Germany
      when /usgov/i
        ::Azure::Armrest::Environment::USGovernment
      else
        ::Azure::Armrest::Environment::Public
      end
    end

    def vms_in_region(azure_res, region)
      filter = "resourceType eq 'Microsoft.Compute/virtualMachines' and location eq '#{region}'"
      azure_res.list_all(:all => true, :filter => filter)
    end
  end
end
