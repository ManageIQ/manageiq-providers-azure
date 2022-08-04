module ManageIQ::Providers::Azure::CloudManager::Provision::Cloning
  def do_clone_task_check(_clone_task_ref)
    source.with_provider_connection do |azure|
      vms      = ::Azure::Armrest::VirtualMachineService.new(azure)
      instance = vms.get(dest_name, resource_group.name)
      status   = instance.properties.provisioning_state
      return true if status == "Succeeded"
      return false, status
    end
  end

  def gather_storage_account_properties
    sas = nil

    source.with_provider_connection do |azure|
      sas = ::Azure::Armrest::StorageAccountService.new(azure)
    end

    return if sas.nil?

    begin
      image = sas.list_private_images(storage_account_resource_group).find do |img|
        img.uri == source.ems_ref
      end

      return unless image

      platform   = image.operating_system
      endpoint   = image.storage_account.properties.primary_endpoints.blob
      source_uri = image.uri

      target_uri = File.join(endpoint, "manageiq", dest_name + "_" + SecureRandom.uuid + ".vhd")
    rescue ::Azure::Armrest::ResourceNotFoundException => err
      _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
    end

    return target_uri, source_uri, platform
  end

  def custom_data
    userdata_payload.encode('UTF-8').delete("\n")
  end

  def prepare_for_clone_task
    # TODO: Ideally this would be a check against source.storage or source.disks
    if source.ems_ref =~ /.+:.+:.+:.+/
      urn_keys = %w(publisher offer sku version)
      image_reference = Hash[urn_keys.zip(source.ems_ref.split(':'))]
      os, target_uri, source_uri = nil
    elsif source.ems_ref.starts_with?('/subscriptions')
      os = source.operating_system.product_name
      target_uri, source_uri = nil
      image_reference = { :id => source.ems_ref }
    else
      image_reference = nil
      target_uri, source_uri, os = gather_storage_account_properties
    end

    cloud_options =
      {
        :name       => dest_name,
        :location   => source.location,
        :properties => {
          :hardwareProfile => {
            :vmSize => instance_type.name
          },
          :osProfile       => {
            :adminUserName => options[:root_username],
            :adminPassword => root_password,
            :computerName  => dest_hostname
          },
          :storageProfile  => {
            :osDisk => {
              :createOption => 'FromImage',
              :caching      => 'ReadWrite',
              :osType       => os
            }
          }
        }
      }

    # The -1 value is set in ProvisionWorkflow to distinguish between the
    # desire for a new Public IP address vs a private IP.
    #
    if floating_ip
      nic_id = associated_nic || create_nic(true)
    else
      public_ip = options[:floating_ip_address].first == -1
      nic_id = create_nic(public_ip)
    end

    cloud_options[:properties][:networkProfile] = {:networkInterfaces => [{:id => nic_id}]}

    if target_uri
      cloud_options[:properties][:storageProfile][:osDisk][:name]  = dest_name + SecureRandom.uuid + '.vhd'
      cloud_options[:properties][:storageProfile][:osDisk][:image] = {:uri => source_uri}
      cloud_options[:properties][:storageProfile][:osDisk][:vhd]   = {:uri => target_uri}
    else
      # Default to a storage account type of "Standard_LRS" for managed images for now.
      cloud_options[:properties][:storageProfile][:osDisk][:managedDisk] = {:storageAccountType => 'Standard_LRS'}
      cloud_options[:properties][:storageProfile][:imageReference] = image_reference
    end

    cloud_options[:properties][:osProfile][:customData] = custom_data unless userdata_payload.nil?

    cloud_options
  end

  def log_clone_options(clone_options)
    dump_obj(clone_options, "#{_log.prefix} Clone Options: ", $log, :info)
    dump_obj(options, "#{_log.prefix} Prov Options:  ", $log, :info, :protected => {:path => workflow_class.encrypted_options_field_regs})
  end

  def region
    source.location
  end

  def storage_account_resource_group
    source.description.split("/").first
  end

  def storage_account_name
    source.description.split("/")[1]
  end

  def associated_nic
    floating_ip.try(:network_port).try(:ems_ref)
  end

  def create_nic(with_public_ip = true)
    source.with_provider_connection do |azure|
      nis = ::Azure::Armrest::Network::NetworkInterfaceService.new(azure)

      if with_public_ip
        ips = ::Azure::Armrest::Network::IpAddressService.new(azure)

        # Use the existing Public IP if possible. Otherwise create a new one.
        if floating_ip.try(:ems_ref)
          begin
            ip = ips.get_by_id(floating_ip.ems_ref)
          rescue ::Azure::Armrest::NotFoundException
            ip = ips.create("#{dest_name}-publicIp", resource_group.name, :location => region)
          end
        else
          ip = ips.create("#{dest_name}-publicIp", resource_group.name, :location => region)
        end

        network_options = build_nic_options(ip.id)
      else
        network_options = build_nic_options
      end

      return nis.create(dest_name, resource_group.name, network_options).id
    end
  end

  def build_nic_options(ip_id = nil)
    ip_config = {
      :name       => dest_name,
      :properties => {
        :subnet => {:id => cloud_subnet.ems_ref}
      }
    }

    ip_config[:properties][:publicIPAddress] = {:id => ip_id} if ip_id

    network_options = {
      :location   => region,
      :properties => {
        :ipConfigurations => [ip_config]
      }
    }

    network_options[:properties][:networkSecurityGroup] = {:id => security_group.ems_ref} if security_group

    network_options
  end

  def start_clone(clone_options)
    source.with_provider_connection do |azure|
      vms = ::Azure::Armrest::VirtualMachineService.new(azure)
      vm  = vms.create(dest_name, resource_group.name, clone_options)

      File.join(azure.subscription_id, vm.resource_group.downcase, vm.type.downcase, vm.name)
    end
  end
end
