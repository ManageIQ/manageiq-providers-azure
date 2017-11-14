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

  def collector_memory_usage
    require 'miq-process'
    MiqProcess.processInfo[:proportional_set_size].to_f / 1.megabyte
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

  # Compose an id string combining some existing keys
  def resource_uid(*keys)
    keys.join('\\')
  end

  # For those resources without a location, default to the location of
  # their resource group.
  #
  def gather_data_for_this_region(arm_service, method_name = 'list_all')
    if method_name.to_s == 'list_all'
      arm_service.send(method_name).select do |resource|
        resource.try(:location).try(:casecmp, @ems.provider_region).zero?
      end.flatten
    elsif method_name.to_s == 'list_all_private_images' # requires special handling
      arm_service.send(method_name, :location => @ems.provider_region)
    else
      resource_groups.collect do |resource_group|
        arm_service.send(method_name, resource_group.name).select do |resource|
          location = resource.respond_to?(:location) ? resource.location : resource_group.location
          location.casecmp(@ems.provider_region).zero?
        end
      end.flatten
    end
  end

  # Because resources do not necessarily have to belong to the same region as
  # the resource group they live in, we do not filter by region here.
  #
  def resource_groups
    @resource_groups ||= @rgs.list
  end

  # Given an object, return the matching ems_ref for its resource group.
  #
  def get_resource_group_ems_ref(object)
    "/subscriptions/#{object.subscription_id}/resourceGroups/#{object.resource_group.downcase}"
  end

  # TODO(lsmola) NetworkManager, move below methods under NetworkManager, once it is not needed in Cloudmanager
  def get_vm_nics(instance)
    nic_ids = instance.properties.network_profile.network_interfaces.collect(&:id)
    network_interfaces.find_all { |nic| nic_ids.include?(nic.id) }
  end

  def network_interfaces
    @network_interfaces ||= gather_data_for_this_region(@nis)
  end

  def ip_addresses
    @ip_addresses ||= gather_data_for_this_region(@ips)
  end

  # Create the necessary service classes and lock down their api-version
  # strings using the config/settings.yml from the provider repo. The
  # "to_s" call for the version strings puts the date in the format
  # that we need, i.e. "YYYY-MM-DD".
  #

  def availability_set_service(config)
    ::Azure::Armrest::AvailabilitySetService.new(config).tap do |service|
      service.api_version = Settings.ems.ems_azure.api_versions.availability_set.to_s
    end
  end

  def ip_address_service(config)
    ::Azure::Armrest::Network::IpAddressService.new(config).tap do |service|
      service.api_version = Settings.ems.ems_azure.api_versions.ip_address.to_s
    end
  end

  def load_balancer_service(config)
    ::Azure::Armrest::Network::LoadBalancerService.new(config).tap do |service|
      service.api_version = Settings.ems.ems_azure.api_versions.load_balancer.to_s
    end
  end

  def managed_image_service(config)
    ::Azure::Armrest::Storage::ImageService.new(config).tap do |service|
      service.api_version = Settings.ems.ems_azure.api_versions.managed_image.to_s
    end
  end

  def virtual_machine_image_service(config, options = {})
    ::Azure::Armrest::VirtualMachineImageService.new(config, options).tap do |service|
      service.api_version = Settings.ems.ems_azure.api_versions.managed_image.to_s
    end
  end

  def network_interface_service(config)
    ::Azure::Armrest::Network::NetworkInterfaceService.new(config).tap do |service|
      service.api_version = Settings.ems.ems_azure.api_versions.network_interface.to_s
    end
  end

  def network_security_group_service(config)
    ::Azure::Armrest::Network::NetworkSecurityGroupService.new(config).tap do |service|
      service.api_version = Settings.ems.ems_azure.api_versions.network_security_group.to_s
    end
  end

  def resource_group_service(config)
    ::Azure::Armrest::ResourceGroupService.new(config).tap do |service|
      service.api_version = Settings.ems.ems_azure.api_versions.resource_group.to_s
    end
  end

  def template_deployment_service(config)
    ::Azure::Armrest::TemplateDeploymentService.new(config).tap do |service|
      service.api_version = Settings.ems.ems_azure.api_versions.template_deployment.to_s
    end
  end

  def storage_account_service(config)
    ::Azure::Armrest::StorageAccountService.new(config).tap do |service|
      service.api_version = Settings.ems.ems_azure.api_versions.storage_account.to_s
    end
  end

  def virtual_machine_service(config)
    ::Azure::Armrest::VirtualMachineService.new(config).tap do |service|
      service.api_version = Settings.ems.ems_azure.api_versions.virtual_machine.to_s
    end
  end

  def virtual_network_service(config)
    ::Azure::Armrest::Network::VirtualNetworkService.new(config).tap do |service|
      service.api_version = Settings.ems.ems_azure.api_versions.virtual_network.to_s
    end
  end
end
