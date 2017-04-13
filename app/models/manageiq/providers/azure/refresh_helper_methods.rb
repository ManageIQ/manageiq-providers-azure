module ManageIQ::Providers::Azure::RefreshHelperMethods
  extend ActiveSupport::Concern

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
        resource.try(:location) == @ems.provider_region
      end.flatten
    elsif method_name.to_s == 'list_all_private_images' # requires special handling
      arm_service.send(method_name, :location => @ems.provider_region)
    else
      resource_groups.collect do |resource_group|
        arm_service.send(method_name, resource_group.name).select do |resource|
          location = resource.respond_to?(:location) ? resource.location : resource_group.location
          location == @ems.provider_region
        end
      end.flatten
    end
  end

  def resource_groups
    @resource_groups ||= @rgs.list.select do |resource_group|
      resource_group.location == @ems.provider_region
    end
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
    @avs ||= ::Azure::Armrest::AvailabilitySetService.new(config)
    @avs.api_version = Settings.ems.ems_azure.api_versions.availability_set.to_s
    @avs
  end

  def ip_address_service(config)
    @ips ||= ::Azure::Armrest::Network::IpAddressService.new(config)
    @ips.api_version = Settings.ems.ems_azure.api_versions.ip_address.to_s
    @ips
  end

  def load_balancer_service(config)
    @lbs ||= ::Azure::Armrest::Network::LoadBalancerService.new(config)
    @lbs.api_version = Settings.ems.ems_azure.api_versions.load_balancer.to_s
    @lbs
  end

  def network_interface_service(config)
    @nis ||= ::Azure::Armrest::Network::NetworkInterfaceService.new(config)
    @nis.api_version = Settings.ems.ems_azure.api_versions.network_interface.to_s
    @nis
  end

  def network_security_group_service(config)
    @nsg ||= ::Azure::Armrest::Network::NetworkSecurityGroupService.new(config)
    @nsg.api_version = Settings.ems.ems_azure.api_versions.network_security_group.to_s
    @nsg
  end

  def resource_group_service(config)
    @rgs ||= ::Azure::Armrest::ResourceGroupService.new(config)
    @rgs.api_version = Settings.ems.ems_azure.api_versions.resource_group.to_s
    @rgs
  end

  def template_deployment_service(config)
    @tds ||= ::Azure::Armrest::TemplateDeploymentService.new(config)
    @tds.api_version = Settings.ems.ems_azure.api_versions.template_deployment.to_s
    @tds
  end

  def storage_account_service(config)
    @sas ||= ::Azure::Armrest::StorageAccountService.new(config)
    @sas.api_version = Settings.ems.ems_azure.api_versions.storage_account.to_s
    @sas
  end

  def virtual_machine_service(config)
    @vms ||= ::Azure::Armrest::VirtualMachineService.new(config)
    @vms.api_version = Settings.ems.ems_azure.api_versions.virtual_machine.to_s
    @vms
  end

  def virtual_network_service(config)
    @vns ||= ::Azure::Armrest::Network::VirtualNetworkService.new(config)
    @vns.api_version = Settings.ems.ems_azure.api_versions.virtual_network.to_s
    @vns
  end
end
