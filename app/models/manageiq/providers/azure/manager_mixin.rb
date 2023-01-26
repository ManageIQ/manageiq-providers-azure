module ManageIQ::Providers::Azure::ManagerMixin
  extend ActiveSupport::Concern

  def connect(options = {})
    raise MiqException::MiqHostError, _("No credentials defined") if missing_credentials?(options[:auth_type])

    client_id  = options[:user] || authentication_userid(options[:auth_type])
    client_key = options[:pass] || authentication_password(options[:auth_type])

    self.class.raw_connect(client_id, client_key, azure_tenant_id, subscription, options[:service], options[:proxy_uri] || http_proxy_uri, provider_region, default_endpoint)
  end

  def verify_credentials(_auth_type = nil, options = {})
    self.class.connection_rescue_block do
      conn = connect(options)

      # Check if the Microsoft.Insights Resource Provider is registered.  If not then
      # neither events nor metrics are supported.
      ms_insights_service = ::Azure::Armrest::ResourceProviderService.new(conn).get('Microsoft.Insights')
      capabilities["insights"] = ms_insights_service.registration_state.casecmp('registered').zero?

      save! if changed?

      true
    end
  end

  module ClassMethods
    private def provider_region_options
      ManageIQ::Providers::Azure::Regions
        .all
        .sort_by { |r| r[:description].downcase }
        .map do |r|
          {
            :label => r[:description],
            :value => r[:name]
          }
        end
    end

    def params_for_create
      {
        :fields => [
          {
            :component    => "select",
            :id           => "provider_region",
            :name         => "provider_region",
            :label        => _("Region"),
            :isRequired   => true,
            :validate     => [{:type => "required"}],
            :includeEmpty => true,
            :options      => provider_region_options
          },
          {
            :component  => "text-field",
            :id         => "uid_ems",
            :name       => "uid_ems",
            :label      => _("Tenant ID"),
            :isRequired => true,
            :validate   => [{:type => "required"}],
          },
          {
            :component  => "text-field",
            :id         => "subscription",
            :name       => "subscription",
            :label      => _("Subscription ID"),
            :isRequired => true,
            :validate   => [{:type => "required"}],
          },
          {
            :component => 'sub-form',
            :id        => 'endpoints-subform',
            :name      => 'endpoints-subform',
            :title     => _("Endpoint"),
            :fields    => [
              {
                :component              => 'validate-provider-credentials',
                :id                     => 'authentications.default.valid',
                :name                   => 'authentications.default.valid',
                :skipSubmit             => true,
                :isRequired             => true,
                :validationDependencies => %w[type zone_id provider_region subscription uid_ems],
                :fields                 => [
                  {
                    :component => "text-field",
                    :id        => "endpoints.default.url",
                    :name      => "endpoints.default.url",
                    :label     => _("Endpoint URL"),
                  },
                  {
                    :component  => "text-field",
                    :id         => "authentications.default.userid",
                    :name       => "authentications.default.userid",
                    :label      => _("Client ID"),
                    :helperText => _("Should have privileged access, such as root or administrator."),
                    :isRequired => true,
                    :validate   => [{:type => "required"}]
                  },
                  {
                    :component  => "password-field",
                    :id         => "authentications.default.password",
                    :name       => "authentications.default.password",
                    :label      => _("Client Key"),
                    :type       => "password",
                    :isRequired => true,
                    :validate   => [{:type => "required"}]
                  },
                ],
              },
            ],
          },
        ],
      }
    end

    # Verify Credentials
    # args:
    # {
    #   "uid_ems"      => "",
    #   "subscription" => "",
    #   "region"       => "",
    #   "endpoints"    => {
    #     "default" => {
    #       "userid"   => "",
    #       "password" => "",
    #       "url"      => ""
    #     }
    #   }
    # }
    def verify_credentials(args)
      region           = args["provider_region"]
      subscription     = args["subscription"]
      azure_tenant_id  = args["uid_ems"]
      default_endpoint = args.dig("authentications", "default")
      endpoint_url = args.dig("endpoints", "default", "url")

      client_id, client_key = default_endpoint&.values_at("userid", "password")

      client_key = ManageIQ::Password.try_decrypt(client_key)
      # Pull out the password from the database if a provider ID is available
      client_key ||= find(args["id"]).authentication_password('default')

      connection_rescue_block do
        conn = raw_connect(client_id, client_key, azure_tenant_id, subscription, nil, http_proxy_uri, region, endpoint_url)

        # Issue a simple API call to list vm series/flavors to ensure VMM service is available for this
        # subscription in this region.
        vmm = ::Azure::Armrest::VirtualMachineService.new(conn)
        vmm.series(region)
      end
    end

    def raw_connect(client_id, client_key, azure_tenant_id, subscription, service = nil, proxy_uri = nil, provider_region = nil, endpoint = nil)
      require 'azure-armrest'

      if subscription.blank?
        raise MiqException::MiqInvalidCredentialsError, _("Incorrect credentials - check your Azure Subscription ID")
      end

      if provider_region.blank?
        $azure_log.warn("No region selected. Validating credentials against public environment.")
      end

      endpoint_url = endpoint.respond_to?(:url) ? endpoint.url : endpoint.to_s

      if endpoint_url.present?
        begin
          environment = ::Azure::Armrest::Environment.discover(:url => endpoint_url, :proxy => proxy_uri)
        rescue SocketError
          raise MiqException::MiqUnreachableError, _("Invalid endpoint")
        end
      else
        environment = environment_for(provider_region)
      end

      ::Azure::Armrest::Configuration.log = $azure_log

      config = ::Azure::Armrest::Configuration.new(
        :client_id       => client_id,
        :client_key      => ManageIQ::Password.try_decrypt(client_key),
        :tenant_id       => azure_tenant_id,
        :subscription_id => subscription,
        :proxy           => proxy_uri,
        :environment     => environment
      )

      case service
      when 'AvailabilitySetService'
        ::Azure::Armrest::AvailabilitySetService.new(config)
      when 'IpAddressService'
        ::Azure::Armrest::Network::IpAddressService.new(config)
      when 'LoadBalancerService'
        ::Azure::Armrest::Network::LoadBalancerService.new(config)
      when 'ImageService'
        ::Azure::Armrest::Storage::ImageService.new(config)
      when 'VirtualMachineImageService'
        ::Azure::Armrest::VirtualMachineImageService.new(config, :location => provider_region)
      when 'NetworkInterfaceService'
        ::Azure::Armrest::Network::NetworkInterfaceService.new(config)
      when 'NetworkSecurityGroupService'
        ::Azure::Armrest::Network::NetworkSecurityGroupService.new(config)
      when 'ResourceGroupService'
        ::Azure::Armrest::ResourceGroupService.new(config)
      when 'ResourceProviderService'
        ::Azure::Armrest::ResourceProviderService.new(config)
      when 'RouteTableService'
        ::Azure::Armrest::Network::RouteTableService.new(config)
      when 'TemplateDeploymentService'
        ::Azure::Armrest::TemplateDeploymentService.new(config)
      when 'DiskService'
        ::Azure::Armrest::Storage::DiskService.new(config)
      when 'StorageAccountService'
        ::Azure::Armrest::StorageAccountService.new(config)
      when 'MysqlServerService'
        ::Azure::Armrest::Sql::MysqlServerService.new(config)
      when 'MysqlDatabaseService'
        ::Azure::Armrest::Sql::MysqlDatabaseService.new(config)
      when 'PostgresqlServerService'
        ::Azure::Armrest::Sql::PostgresqlServerService.new(config)
      when 'PostgresqlDatabaseService'
        ::Azure::Armrest::Sql::PostgresqlDatabaseService.new(config)
      when 'SqlServerService'
        ::Azure::Armrest::Sql::SqlServerService.new(config)
      when 'SqlDatabaseService'
        ::Azure::Armrest::Sql::SqlDatabaseService.new(config)
      when 'VirtualMachineService'
        ::Azure::Armrest::VirtualMachineService.new(config)
      when 'VirtualNetworkService'
        ::Azure::Armrest::Network::VirtualNetworkService.new(config)
      else
        config
      end
    end

    def connection_rescue_block
      require 'azure-armrest'
      yield
    rescue ArgumentError => err
      raise MiqException::MiqInvalidCredentialsError, _("Incorrect credentials - %{error_message}") % {:error_message => err.message}
    rescue ::Azure::Armrest::UnauthorizedException, ::Azure::Armrest::BadRequestException
      raise MiqException::MiqInvalidCredentialsError, _("Incorrect credentials - check your Azure Tenant ID, Client ID, and Client Key")
    rescue MiqException::MiqInvalidCredentialsError
      raise # Raise before falling into catch-all block below
    rescue StandardError => err
      _log.error("Error Class=#{err.class.name}, Message=#{err.message}, Backtrace=#{err.backtrace}")
      raise err, _("Unexpected response returned from system: %{error_message}") % {:error_message => err.message}
    end

    def environment_for(region)
      case region
      when /usgov/i
        ::Azure::Armrest::Environment::USGovernment
      else
        ::Azure::Armrest::Environment::Public
      end
    end

    # Discovery

    # Create EmsAzure instances for all regions with instances
    # or images for the given authentication. Created EmsAzure instances
    # will automatically have EmsRefreshes queued up.  If this is a greenfield
    # discovery, we will at least add an EmsAzure for eastus
    def discover(clientid, clientkey, azure_tenant_id, subscription)
      new_emses = []

      all_emses = includes(:authentications)
      all_ems_names = all_emses.index_by(&:name)

      known_emses = all_emses.select { |e| e.authentication_userid == clientid }
      known_ems_regions = known_emses.index_by(&:provider_region)

      config = raw_connect(clientid, clientkey, azure_tenant_id, subscription)

      azure_res = ::Azure::Armrest::ResourceService.new(config)
      azure_res.api_version = Settings.ems.ems_azure.api_versions.resource

      azure_res.list_locations.each do |region|
        next if known_ems_regions.include?(region.name)
        next if vms_in_region(azure_res, region.name).count.zero? # instances
        # TODO: Check if images are == 0 and if so then skip
        new_emses << create_discovered_region(region.name, clientid, clientkey, azure_tenant_id, subscription, all_ems_names)
      end

      # at least create the Azure-eastus region.
      if new_emses.blank? && known_emses.blank?
        new_emses << create_discovered_region("eastus", clientid, clientkey, azure_tenant_id, subscription, all_ems_names)
      end

      EmsRefresh.queue_refresh(new_emses) if new_emses.present?

      new_emses
    end

    def discover_queue(clientid, clientkey, azure_tenant_id, subscription)
      MiqQueue.put(
        :class_name  => name,
        :method_name => "discover_from_queue",
        :args        => [clientid, ManageIQ::Password.encrypt(clientkey), azure_tenant_id, subscription]
      )
    end

    def vms_in_region(azure_res, region)
      filter = "resourceType eq 'Microsoft.Compute/virtualMachines' and location eq '#{region}'"
      azure_res.list_all(:all => true, :filter => filter)
    end

    def discover_from_queue(clientid, clientkey, azure_tenant_id, subscription)
      discover(clientid, ManageIQ::Password.decrypt(clientkey), azure_tenant_id, subscription)
    end

    def create_discovered_region(region_name, clientid, clientkey, azure_tenant_id, subscription, all_ems_names)
      name = "Azure-#{region_name}"
      name = "Azure-#{region_name} #{clientid}" if all_ems_names.key?(name)

      while all_ems_names.key?(name)
        name_counter = name_counter.to_i + 1 if defined?(name_counter)
        name = "Azure-#{region_name} #{name_counter}"
      end

      new_ems = create!(
        :name            => name,
        :provider_region => region_name,
        :zone            => Zone.default_zone,
        :uid_ems         => azure_tenant_id,
        :subscription    => subscription
      )
      new_ems.update_authentication(
        :default => {
          :userid   => clientid,
          :password => clientkey
        }
      )
      new_ems
    end
  end
end
