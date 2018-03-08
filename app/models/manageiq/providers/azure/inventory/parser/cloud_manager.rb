# TODO: Separate collection from parsing (perhaps collecting in parallel a la RHEVM)

class ManageIQ::Providers::Azure::Inventory::Parser::CloudManager < ManageIQ::Providers::Azure::Inventory::Parser
  def parse
    log_header = "Collecting data for EMS : [#{collector.manager.name}] id: [#{collector.manager.id}]"

    _log.info("#{log_header}...")

    resource_groups
    flavors
    availability_zones
    stacks
    stack_templates
    instances
    managed_images
    images
    market_images if collector.options.get_market_images

    _log.info("#{log_header}...Complete")
  end

  private

  def resource_groups
    collector.resource_groups.each do |resource_group|
      uid = resource_group.id.downcase
      persister.resource_groups.build(
        :name    => resource_group.name,
        :ems_ref => uid,
      )
    end
  end

  def flavors
    collector.flavors.each do |flavor|
      name = uid = flavor.name.downcase
      persister.flavors.build(
        :ems_ref        => uid,
        :name           => name,
        :cpus           => flavor.number_of_cores, # where are the virtual CPUs??
        :cpu_cores      => flavor.number_of_cores,
        :memory         => flavor.memory_in_mb.megabytes,
        :root_disk_size => flavor.os_disk_size_in_mb * 1024,
        :swap_disk_size => flavor.resource_disk_size_in_mb * 1024,
        :enabled        => true
      )
    end
  end

  def availability_zones
    collector.availability_zones.each do |az|
      id = az.id.downcase

      persister.availability_zones.build(
        :ems_ref => id,
        :name    => az.name,
      )
    end
  end

  def instances
    collector.instances.each do |instance|
      uid = resource_uid(collector.subscription_id,
                         instance.resource_group.downcase,
                         instance.type.downcase,
                         instance.name)

      # TODO(lsmola) we have a non lazy dependency, can we remove that?
      series = persister.flavors.find(instance.properties.hardware_profile.vm_size.downcase)

      rg_ems_ref = collector.get_resource_group_ems_ref(instance)

      persister_instance = persister.vms.build(
        :uid_ems             => uid,
        :ems_ref             => uid,
        :name                => instance.name,
        :vendor              => "azure",
        :raw_power_state     => collector.power_status(instance),
        :flavor              => series,
        :location            => instance.location,
        # TODO(lsmola) for release > g, we can use secondary indexes for this as
        :orchestration_stack => persister.stack_resources_secondary_index[instance.id.downcase],
        :availability_zone   => persister.availability_zones.lazy_find('default'),
        :resource_group      => persister.resource_groups.lazy_find(rg_ems_ref),
      )

      instance_hardware(persister_instance, instance, series)
      instance_operating_system(persister_instance, instance)
    end
  end

  def instance_hardware(persister_instance, instance, series)
    persister_hardware = persister.hardwares.build(
      :vm_or_template  => persister_instance,
      :cpu_sockets     => series[:cpus],
      :cpu_total_cores => series[:cpus],
      :memory_mb       => series[:memory] / 1.megabyte,
      :disk_capacity   => series[:root_disk_size] + series[:swap_disk_size],
    )

    hardware_networks(persister_hardware, instance)
    hardware_disks(persister_hardware, instance)
  end

  def instance_operating_system(persister_instance, instance)
    persister.operating_systems.build(
      :vm_or_template => persister_instance,
      :product_name   => guest_os(instance)
    )
  end

  def hardware_networks(persister_hardware, instance)
    collector.get_vm_nics(instance).each do |nic_profile|
      nic_profile.properties.ip_configurations.each do |ipconfig|
        hostname        = ipconfig.name
        private_ip_addr = ipconfig.properties.try(:private_ip_address)
        if private_ip_addr
          hardware_network(persister_hardware, private_ip_addr, hostname, "private")
        end

        public_ip_obj = ipconfig.properties.try(:public_ip_address)
        next unless public_ip_obj

        ip_profile = collector.ip_addresses.find { |ip| ip.id == public_ip_obj.id }
        next unless ip_profile

        public_ip_addr = ip_profile.properties.try(:ip_address)
        hardware_network(persister_hardware, public_ip_addr, hostname, "public")
      end
    end
  end

  def hardware_network(persister_hardware, ip_address, hostname, description)
    persister.networks.build(
      :hardware    => persister_hardware,
      :description => description,
      :ipaddress   => ip_address,
      :hostname    => hostname,
    )
  end

  def hardware_disks(persister_hardware, instance)
    data_disks = instance.properties.storage_profile.data_disks
    data_disks.each do |disk|
      add_instance_disk(persister_hardware, instance, disk)
    end

    disk = instance.properties.storage_profile.os_disk
    add_instance_disk(persister_hardware, instance, disk)
  end

  # Redefine the inherited method for our purposes
  def add_instance_disk(persister_hardware, instance, disk)
    if instance.managed_disk?
      disk_type     = 'managed'
      disk_location = disk.managed_disk.id
      managed_disk  = collector.managed_disks.find { |d| d.id.casecmp(disk_location).zero? }

      if managed_disk
        disk_size = managed_disk.properties.disk_size_gb.gigabytes
        mode      = managed_disk.sku.name
      else
        _log.warn("Unable to find disk information for #{instance.name}/#{instance.resource_group}")
        disk_size = nil
        mode      = nil
      end
    else
      disk_type     = 'unmanaged'
      disk_location = disk.try(:vhd).try(:uri)
      disk_size     = disk.try(:disk_size_gb).try(:gigabytes)

      if disk_location
        uri = Addressable::URI.parse(disk_location)
        storage_name = uri.host.split('.').first
        container_name = File.dirname(uri.path)
        blob_name = uri.basename

        storage_acct = collector.storage_accounts.find { |s| s.name.casecmp(storage_name).zero? }
        mode = storage_acct.sku.name

        if collector.options.get_unmanaged_disk_space && disk_size.nil?
          storage_keys = collector.account_keys(storage_acct)
          storage_key  = storage_keys['key1'] || storage_keys['key2']
          blob_props   = storage_acct.blob_properties(container_name, blob_name, storage_key)
          disk_size    = blob_props.content_length.to_i
        end
      end
    end

    persister.disks.build(
      :hardware        => persister_hardware,
      :device_type     => 'disk',
      :controller_type => 'azure',
      :device_name     => disk.name,
      :location        => disk_location,
      :size            => disk_size,
      :disk_type       => disk_type,
      :mode            => mode
    )
  end

  def stacks
    collector.stacks.each do |deployment|
      name = deployment.name
      uid  = deployment.id

      persister_orchestration_stack = persister.orchestration_stacks.build(
        :ems_ref                => uid,
        :name                   => name,
        :description            => name,
        :status                 => deployment.properties.provisioning_state,
        :resource_group         => deployment.resource_group,
        :orchestration_template => persister.orchestration_templates.lazy_find(uid),
      )

      stack_resources(persister_orchestration_stack, deployment)
      stack_outputs(persister_orchestration_stack, deployment)
      stack_parameters(persister_orchestration_stack, deployment)
    end

    # TODO(lsmola) for release > g, we can use secondary indexes for this as
    # :parent => persister.orchestration_stacks_resources.lazy_find({:ems_ref => res_uid } , {:key => :stack, :ref => :by_...}),
    persister.orchestration_stacks.data.each do |stack_data|
      stack_data[:parent] = persister.stack_resources_secondary_index[stack_data[:ems_ref].downcase]
    end
  end

  def stack_parameters(persister_orchestration_stack, deployment)
    raw_parameters = deployment.properties.try(:parameters)
    return [] if raw_parameters.blank?

    raw_parameters.each do |param_key, param_obj|
      uid = resource_uid(deployment.id, param_key)
      persister.orchestration_stacks_parameters.build(
        :stack   => persister_orchestration_stack,
        :ems_ref => uid,
        :name    => param_key,
        :value   => param_obj['value']
      )
    end
  end

  def stack_outputs(persister_orchestration_stack, deployment)
    raw_outputs = deployment.properties.try(:outputs)
    return [] if raw_outputs.blank?

    raw_outputs.each do |output_key, output_obj|
      uid = resource_uid(deployment.id, output_key)
      persister.orchestration_stacks_outputs.build(
        :stack       => persister_orchestration_stack,
        :ems_ref     => uid,
        :key         => output_key,
        :value       => output_obj['value'],
        :description => output_key
      )
    end
  end

  def stack_resources(persister_orchestration_stack, deployment)
    collector.stack_resources(deployment).each do |resource|
      status_message = resource_status_message(resource)
      status_code = resource.properties.try(:status_code)
      persister_stack_resource = persister.orchestration_stacks_resources.build(
        :stack                  => persister_orchestration_stack,
        :ems_ref                => resource.properties.target_resource.id,
        :name                   => resource.properties.target_resource.resource_name,
        :logical_resource       => resource.properties.target_resource.resource_name,
        :physical_resource      => resource.properties.tracking_id,
        :resource_category      => resource.properties.target_resource.resource_type,
        :resource_status        => resource.properties.provisioning_state,
        :resource_status_reason => status_message || status_code,
        :last_updated           => resource.properties.timestamp
      )

      # TODO(lsmola) for release > g, we can use secondary indexes for this
      persister.stack_resources_secondary_index[persister_stack_resource[:ems_ref].downcase] = persister_stack_resource[:stack]
    end
  end

  def stack_templates
    collector.stack_templates.each do |template|
      persister.orchestration_templates.build(
        :ems_ref     => template[:uid],
        :name        => template[:name],
        :description => template[:description],
        :content     => template[:content],
        :orderable   => false
      )
    end
  end

  def managed_images
    collector.managed_images.each do |image|
      uid = image.id.downcase
      rg_ems_ref = collector.get_resource_group_ems_ref(image)

      persister_miq_template = persister.miq_templates.build(
        :uid_ems            => uid,
        :ems_ref            => uid,
        :name               => image.name,
        :description        => "#{image.resource_group}\\#{image.name}",
        :location           => collector.manager.provider_region,
        :vendor             => 'azure',
        :raw_power_state    => 'never',
        :template           => true,
        :publicly_available => false,
        :resource_group     => persister.resource_groups.lazy_find(rg_ems_ref),
      )

      image_hardware(persister_miq_template, image.properties.storage_profile.try(:os_disk).try(:os_type) || 'unknown')
      image_operating_system(persister_miq_template, image)
    end
  end

  def market_images
    collector.market_images.each do |image|
      uid = image.id

      persister_miq_template = persister.miq_templates.build(
        :uid_ems            => uid,
        :ems_ref            => uid,
        :name               => "#{image.offer} - #{image.sku} - #{image.version}",
        :description        => "#{image.offer} - #{image.sku} - #{image.version}",
        :location           => collector.manager.provider_region,
        :vendor             => 'azure',
        :raw_power_state    => 'never',
        :template           => true,
        :publicly_available => true,
      )

      image_hardware(persister_miq_template, 'unknown')
    end
  end

  def images
    collector.images.each do |image|
      uid = image.uri

      persister_miq_template = persister.miq_templates.build(
        :uid_ems            => uid,
        :ems_ref            => uid,
        :name               => build_image_name(image),
        :description        => build_image_description(image),
        :location           => collector.manager.provider_region,
        :vendor             => "azure",
        :raw_power_state    => "never",
        :template           => true,
        :publicly_available => false,
      )

      image_hardware(persister_miq_template, image.operating_system)
    end
  end

  def image_hardware(persister_miq_template, os)
    persister.hardwares.build(
      :vm_or_template => persister_miq_template,
      :bitness        => 64,
      :guest_os       => OperatingSystem.normalize_os_name(os)
    )
  end

  def image_operating_system(persister_miq_template, image)
    persister.operating_systems.build(
      :vm_or_template => persister_miq_template,
      :product_name   => guest_os(image)
    )
  end

  # Helper methods
  # #################

  # Find both OS and SKU if possible, otherwise just the OS type.
  def guest_os(instance)
    image_reference = instance.properties.storage_profile.try(:image_reference)
    if image_reference&.try(:offer)
      "#{image_reference.offer} #{image_reference.sku.tr('-', ' ')}"
    else
      instance.properties.storage_profile.os_disk.os_type
    end
  end

  def resource_status_message(resource)
    return nil unless resource.properties.respond_to?(:status_message)
    if resource.properties.status_message.respond_to?(:error)
      resource.properties.status_message.error.message
    else
      resource.properties.status_message.to_s
    end
  end

  def build_image_name(image)
    # Strip the .vhd and Azure GUID extension, but retain path and base name.
    File.join(File.dirname(image.name), File.basename(File.basename(image.name, '.*'), '.*'))
  end

  def build_image_description(image)
    # Description is a concatenation of resource group and storage account
    "#{image.storage_account.resource_group}\\#{image.storage_account.name}"
  end
end
