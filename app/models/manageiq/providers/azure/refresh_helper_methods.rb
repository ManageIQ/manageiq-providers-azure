module ManageIQ::Providers::Azure::RefreshHelperMethods
  extend ActiveSupport::Concern

  def collect_inventory(inv_type)
    collection_name = inv_type.to_s.titleize

    _log.info("Retrieving #{collection_name}...")

    inventory = yield
    inv_count = inventory.blank? ? 0 : inventory.length

    _log.info("Retrieving #{collection_name}...Complete - Count [#{inv_count}]")
    _log.debug("Memory usage: #{'%.02f' % collector_memory_usage} MiB")

    inventory
  end

  def collect_inventory_targeted(inv_type)
    collection_name = inv_type.to_s.titleize

    _log.debug("Retrieving Targeted #{collection_name}...")

    inventory = yield
    inv_count = inventory.blank? ? 0 : inventory.length

    _log.debug("Retrieving Targeted #{collection_name}...Complete - Count [#{inv_count}]")
    _log.debug("Memory usage: #{'%.02f' % collector_memory_usage} MiB")

    inventory.try(:compact)
  end

  def collector_memory_usage
    require 'miq-process'
    MiqProcess.processInfo[:proportional_set_size].to_f / 1.megabyte
  end

  # Strip the .vhd and Azure GUID extension, but retain path and base name.
  #
  def build_image_name(image)
    path = File.join(File.dirname(image.name), File.basename(File.basename(image.name, '.*'), '.*'))
    Pathname.new(path).cleanpath.to_s
  end

  # Return the parent image for the given instance, if possible. Note that we
  # cannot currently find the parent if it is a marketplace image.
  #
  def parent_ems_ref(instance)
    if instance.managed_disk?
      instance.properties.storage_profile.try(:image_reference).try(:id).try(:downcase)
    else
      instance.properties.storage_profile.try(:os_disk).try(:image).try(:uri)
    end
  end

  def process_collection(collection, key, store_in_data = true)
    @data[key] ||= [] if store_in_data

    return if collection.nil?

    collection.each do |item|
      uid, new_result = yield(item)
      @data[key] << new_result if store_in_data
      @data_index.store_path(key, uid, new_result)
    end
  end

  def filter_my_region(resources = nil)
    resources = yield if block_given?

    Array.wrap(resources)
         .compact
         .select { |resource| resource.try(:location).try(:casecmp, @ems.provider_region).zero? }
  end

  def filter_my_region_parallel_map(refs, in_threads: thread_limit, &block)
    filter_my_region { Parallel.map(refs, :in_threads => in_threads, &block) }
  end

  # Because resources do not necessarily have to belong to the same region as
  # the resource group they live in, we do not filter by region here.
  #
  def get_resource_groups
    @resource_groups ||= @rgs.list(:all => true)
  end

  # Given an object, return the matching ems_ref for its resource group.
  #
  def get_resource_group_ems_ref(object)
    "/subscriptions/#{object.subscription_id}/resourcegroups/#{object.resource_group}".downcase
  end

  # Create the necessary service classes and lock down their api-version
  # strings using the config/settings.yml from the provider repo.

  def cached_resource_provider_service(config)
    @cached_resource_provider_service ||= resource_provider_service(config)
  end

  # If the api-version string set in settings.yml is invalid, a warning
  # will be issued, and it will default to the most recent valid string.
  #
  def valid_api_version(config, service, name)
    config_api_version = Settings.ems.ems_azure.api_versions[name]

    unless cached_resource_provider_service(config).supported?(service.service_name, service.provider)
      return config_api_version
    end

    valid_api_versions = cached_resource_provider_service(config).list_api_versions(service.provider, service.service_name)

    if valid_api_versions.include?(config_api_version)
      config_api_version
    else
      valid_version_string = valid_api_versions.first

      message = "Invalid api-version setting of '#{config_api_version}' for " \
        "#{service.provider}/#{service.service_name} for EMS #{@ems.name}; " \
        "using '#{valid_version_string}' instead."

      _log.warn(message)
      valid_version_string
    end
  end

  def availability_set_service(config)
    ::Azure::Armrest::AvailabilitySetService.new(config).tap do |service|
      service.api_version = valid_api_version(config, service, 'availability_set')
    end
  end

  def ip_address_service(config)
    ::Azure::Armrest::Network::IpAddressService.new(config).tap do |service|
      service.api_version = valid_api_version(config, service, 'ip_address')
    end
  end

  def load_balancer_service(config)
    ::Azure::Armrest::Network::LoadBalancerService.new(config).tap do |service|
      service.api_version = valid_api_version(config, service, 'load_balancer')
    end
  end

  def managed_image_service(config)
    ::Azure::Armrest::Storage::ImageService.new(config).tap do |service|
      service.api_version = valid_api_version(config, service, 'managed_image')
    end
  end

  def virtual_machine_image_service(config, options = {})
    ::Azure::Armrest::VirtualMachineImageService.new(config, options).tap do |service|
      service.api_version = valid_api_version(config, service, 'managed_image')
    end
  end

  def network_interface_service(config)
    ::Azure::Armrest::Network::NetworkInterfaceService.new(config).tap do |service|
      service.api_version = valid_api_version(config, service, 'network_interface')
    end
  end

  def network_security_group_service(config)
    ::Azure::Armrest::Network::NetworkSecurityGroupService.new(config).tap do |service|
      service.api_version = valid_api_version(config, service, 'network_security_group')
    end
  end

  def resource_group_service(config)
    ::Azure::Armrest::ResourceGroupService.new(config).tap do |service|
      service.api_version = valid_api_version(config, service, 'resource_group')
    end
  end

  def resource_provider_service(config)
    ::Azure::Armrest::ResourceProviderService.new(config).tap do |service|
      service.api_version = Settings.ems.ems_azure.api_versions.resource_provider
    end
  end

  def route_table_service(config)
    ::Azure::Armrest::Network::RouteTableService.new(config).tap do |service|
      service.api_version = valid_api_version(config, service, 'route_table')
    end
  end

  def template_deployment_service(config)
    ::Azure::Armrest::TemplateDeploymentService.new(config).tap do |service|
      service.api_version = valid_api_version(config, service, 'template_deployment')
    end
  end

  def storage_disk_service(config)
    ::Azure::Armrest::Storage::DiskService.new(config).tap do |service|
      service.api_version = valid_api_version(config, service, 'storage_disk')
    end
  end

  def storage_account_service(config)
    ::Azure::Armrest::StorageAccountService.new(config).tap do |service|
      service.api_version = valid_api_version(config, service, 'storage_account')
    end
  end

  def mariadb_server_service(config)
    ::Azure::Armrest::Sql::MariadbServerService.new(config) do |service|
      service.api_version = valid_api_version(config, service, 'mariadb_server')
    end
  end

  def mariadb_database_service(config)
    ::Azure::Armrest::Sql::MariadbDatabaseService.new(config) do |service|
      service.api_version = valid_api_version(config, service, 'mariadb_database')
    end
  end

  def mysql_server_service(config)
    ::Azure::Armrest::Sql::MysqlServerService.new(config) do |service|
      service.api_version = valid_api_version(config, service, 'mysql_server')
    end
  end

  def mysql_database_service(config)
    ::Azure::Armrest::Sql::MysqlDatabaseService.new(config) do |service|
      service.api_version = valid_api_version(config, service, 'mysql_database')
    end
  end

  def postgresql_db_service(config)
    ::Azure::Armrest::Sql::PostgresqlDatabaseService.new(config) do |service|
      service.api_version = valid_api_version(config, service, 'postgresql_database')
    end
  end

  def postgresql_server_service(config)
    ::Azure::Armrest::Sql::PostgresqlServerService.new(config) do |service|
      service.api_version = valid_api_version(config, service, 'postgresql_server')
    end
  end

  def sql_server_service(config)
    ::Azure::Armrest::Sql::SqlServerService.new(config) do |service|
      service.api_version = valid_api_version(config, service, 'sql_server')
    end
  end

  def sql_db_service(config)
    ::Azure::Armrest::Sql::SqlDatabaseService.new(config) do |service|
      service.api_version = valid_api_version(config, service, 'sql_server')
    end
  end

  def virtual_machine_service(config)
    ::Azure::Armrest::VirtualMachineService.new(config).tap do |service|
      service.api_version = valid_api_version(config, service, 'virtual_machine')
    end
  end

  def virtual_network_service(config)
    ::Azure::Armrest::Network::VirtualNetworkService.new(config).tap do |service|
      service.api_version = valid_api_version(config, service, 'virtual_network')
    end
  end

  def provider_region_description
    @provider_region_description ||= ManageIQ::Providers::Azure::Regions.regions.dig(@ems.provider_region, :description)
  end
end
