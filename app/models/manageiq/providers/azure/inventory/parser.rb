class ManageIQ::Providers::Azure::Inventory::Parser < ManageIQ::Providers::Inventory::Parser
  require_nested :CloudManager
  require_nested :NetworkManager

  include Vmdb::Logging
  include ManageIQ::Providers::Azure::RefreshHelperMethods

  TYPE_DEPLOYMENT = "microsoft.resources/deployments".freeze

  def parse
    log_header = "Collecting data for EMS : [#{collector.manager.name}] id: [#{collector.manager.id}]"

    @data_index = {}

    _log.info("#{log_header}...")

    resource_groups
    flavors
    availability_zones
    stacks
    stack_templates
    instances
    managed_images
    images if collector.options.get_private_images
    market_images if collector.options.get_market_images
    security_groups
    cloud_networks
    network_ports
    load_balancers
    floating_ips
    network_routers

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
      name = flavor.name

      persister.flavors.build(
        :ems_ref        => name.downcase,
        :name           => name,
        :cpus           => flavor.number_of_cores, # where are the virtual CPUs??
        :cpu_cores      => flavor.number_of_cores,
        :memory         => flavor.memory_in_mb.megabytes,
        :root_disk_size => flavor.os_disk_size_in_mb.megabytes,
        :swap_disk_size => flavor.resource_disk_size_in_mb.megabytes,
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
      uid = File.join(collector.subscription_id,
                      instance.resource_group.downcase,
                      instance.type.downcase,
                      instance.name)

      # TODO(lsmola) we have a non lazy dependency, can we remove that?
      series = persister.flavors.find(instance.properties.hardware_profile.vm_size.downcase)

      rg_ems_ref = collector.get_resource_group_ems_ref(instance)
      parent_ref = collector.parent_ems_ref(instance)

      # We want to archive VMs with no status
      next if (status = collector.power_status(instance)).blank?

      persister_instance = persister.vms.build(
        :uid_ems             => instance.properties.vm_id,
        :ems_ref             => uid,
        :name                => instance.name,
        :vendor              => "azure",
        :connection_state    => "connected",
        :raw_power_state     => status,
        :flavor              => series,
        :location            => instance.location,
        :genealogy_parent    => persister.miq_templates.lazy_find(parent_ref),
        # TODO(lsmola) for release > g, we can use secondary indexes for this as
        :orchestration_stack => persister.stack_resources_secondary_index[instance.id.downcase],
        :availability_zone   => persister.availability_zones.lazy_find('default'),
        :resource_group      => persister.resource_groups.lazy_find(rg_ems_ref),
      )

      instance_hardware(persister_instance, instance, series)
      instance_operating_system(persister_instance, instance)

      vm_and_template_labels(persister_instance, instance['tags'] || [])
      vm_and_template_taggings(persister_instance, map_labels('VmAzure', instance['tags'] || []))
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
    collector.instance_network_ports(instance).each do |nic_profile|
      nic_profile.properties.ip_configurations.each do |ipconfig|
        hostname        = ipconfig.name
        private_ip_addr = ipconfig.properties.try(:private_ip_address)
        if private_ip_addr
          hardware_network(persister_hardware, private_ip_addr, hostname, "private")
        end

        public_ip_obj = ipconfig.properties.try(:public_ip_address)
        next unless public_ip_obj

        ip_profile = collector.instance_floating_ip(public_ip_obj)
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
      managed_disk  = collector.instance_managed_disk(disk_location)

      if managed_disk
        disk_size = managed_disk.properties.disk_size_gb.gigabytes
        mode      = managed_disk.try(:sku).try(:name)
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

        storage_acct = collector.instance_storage_accounts(storage_name)
        mode = storage_acct.try(:sku).try(:name)

        if collector.options.get_unmanaged_disk_space && disk_size.nil? && storage_acct.present?
          storage_keys = collector.instance_account_keys(storage_acct)
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

  def vm_and_template_labels(resource, tags)
    tags.each do |tag|
      persister
        .vm_and_template_labels
        .find_or_build_by(
          :resource => resource,
          :name     => tag.first,
        )
        .assign_attributes(
          :section => 'labels',
          :source  => 'azure',
          :value   => tag.second,
        )
    end
  end

  # Returns array of InventoryObject<Tag>.
  def map_labels(model_name, labels)
    label_hashes = labels.collect do |tag|
      { :name => tag.first, :value => tag.second }
    end
    persister.tag_mapper.map_labels(model_name, label_hashes)
  end

  def vm_and_template_taggings(resource, tags_inventory_objects)
    tags_inventory_objects.each do |tag|
      persister.vm_and_template_taggings.build(:taggable => resource, :tag => tag)
    end
  end

  def stacks
    collector.stacks.each do |deployment|
      name = deployment.name
      uid  = deployment.id

      persister_orchestration_stack = persister.orchestration_stacks.build(
        :ems_ref        => uid,
        :name           => name,
        :description    => name,
        :status         => deployment.properties.provisioning_state,
        :finish_time    => deployment.properties.timestamp,
        :resource_group => deployment.resource_group,
      )

      if (resources = collector.stacks_resources_cache[uid])
        # If the stack hasn't changed, we load existing resources in batches from our DB, this saves a lot of time
        # comparing to doing API query for resources per each stack
        stack_resources_from_cache(persister_orchestration_stack, resources)
      else
        stack_resources(persister_orchestration_stack, deployment)
      end

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
      uid = File.join(deployment.id, param_key)
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
      uid = File.join(deployment.id, output_key)
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

  def stack_resources_from_cache(persister_orchestration_stack, resources)
    resources.each do |resource|
      persister_stack_resource = persister.orchestration_stacks_resources.build(
        resource.merge!(:stack => persister_orchestration_stack)
      )

      # TODO(lsmola) for release > g, we can use secondary indexes for this
      persister.stack_resources_secondary_index[persister_stack_resource[:ems_ref].downcase] = persister_stack_resource[:stack]
    end
  end

  def stack_templates
    collector.stack_templates.each do |template|
      persister_orchestration_template = persister.orchestration_templates.build(
        :ems_ref     => template[:uid],
        :name        => template[:name],
        :description => template[:description],
        :content     => template[:content],
        :orderable   => false
      )

      # Assign template to stack here, so we don't need to always load the template
      persister_orchestration_stack = persister.orchestration_stacks.build(:ems_ref => template[:uid])
      persister_orchestration_stack[:orchestration_template] = persister_orchestration_template if persister_orchestration_stack
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
        :description        => "#{image.resource_group}/#{image.name}",
        :location           => collector.manager.provider_region,
        :vendor             => 'azure',
        :connection_state   => "connected",
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
        :connection_state   => "connected",
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
        :connection_state   => "connected",
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

  def build_image_description(image)
    # Description is a concatenation of resource group and storage account
    "#{image.storage_account.resource_group}/#{image.storage_account.name}"
  end

  def security_groups
    collector.security_groups.each do |security_group|
      uid = security_group.id

      description = [
        security_group.resource_group,
        security_group.location
      ].join('-')

      persister_security_group = persister.security_groups.build(
        :ems_ref     => uid,
        :name        => security_group.name,
        :description => description,
      )

      firewall_rules(persister_security_group, security_group)
    end
  end

  def firewall_rules(persister_security_group, security_group)
    security_group.properties.security_rules.each do |rule|
      persister.firewall_rules.build(
        :resource              => persister_security_group,
        :name                  => rule.name,
        :host_protocol         => rule.properties.protocol.upcase,
        :port                  => calculate_start_port(rule),
        :end_port              => calculate_end_port(rule),
        :direction             => rule.properties.direction,
        :source_ip_range       => calculate_source_ip_range(rule),
        :source_security_group => persister.security_groups.lazy_find(security_group.id),
      )
    end
  end

  def cloud_networks
    # TODO(lsmola) solve with secondary indexes for version > g
    if persister.stack_resources_secondary_index.blank?
      manager = persister.manager.respond_to?(:parent_manager) ? persister.manager.parent_manager : persister.manager

      manager.orchestration_stacks_resources.find_each do |resource|
        persister.stack_resources_secondary_index[resource[:ems_ref].downcase] ||=
          InventoryRefresh::ApplicationRecordReference.new(OrchestrationStack, resource.stack_id)
      end
    end

    collector.cloud_networks.each do |cloud_network|
      uid = cloud_network.id

      persister_cloud_networks = persister.cloud_networks.build(
        :ems_ref             => uid,
        :name                => cloud_network.name,
        :cidr                => cloud_network.properties.address_space.address_prefixes.join(", "),
        :enabled             => true,
        :orchestration_stack => persister.stack_resources_secondary_index[uid.downcase],
      )

      cloud_subnets(persister_cloud_networks, cloud_network)
    end
  end

  def cloud_subnets(persister_cloud_networks, cloud_network)
    cloud_network.properties.subnets.each do |subnet|
      uid = subnet.id
      persister.cloud_subnets.build(
        :ems_ref           => uid,
        :name              => subnet.name,
        :cidr              => subnet.properties.address_prefix,
        :cloud_network     => persister_cloud_networks,
        :availability_zone => persister.availability_zones.lazy_find('default'),
        :network_router    => persister.network_routers.lazy_find(subnet.properties.try(:route_table).try(:id))
      )
    end
  end

  def network_routers
    collector.network_routers.each do |router|
      persister.network_routers.build(
        :ems_ref          => router.id,
        :name             => router.name,
        :type             => ManageIQ::Providers::Azure::NetworkManager::NetworkRouter.name,
        :status           => router.properties.try(:subnets) ? 'active' : 'inactive',
        :extra_attributes => { :routes => get_route_attributes(router) }
      )
    end
  end

  def get_route_attributes(router)
    router.properties.routes.map do |route|
      {
        'Name'           => route.name,
        'Resource Group' => route.resource_group,
        'CIDR'           => route.properties.address_prefix
      }
    end
  end

  def network_ports
    collector.network_ports.each do |network_port|
      uid = network_port.id

      vm_id = resource_id_for_instance_id(network_port.properties.try(:virtual_machine).try(:id))

      security_groups = [
        persister.security_groups.lazy_find(network_port.properties.try(:network_security_group).try(:id))
      ].compact

      persister_network_port = persister.network_ports.build(
        :name            => network_port.name,
        :ems_ref         => uid,
        :status          => network_port.properties.try(:provisioning_state),
        :mac_address     => network_port.properties.try(:mac_address),
        :device_ref      => network_port.properties.try(:virtual_machine).try(:id),
        :device          => persister.vms.lazy_find(vm_id),
        :security_groups => security_groups,
        :source          => "refresh",
      )

      network_port.properties.ip_configurations.map do |x|
        persister.cloud_subnet_network_ports.build(
          :address      => x.properties.try(:private_ip_address),
          :cloud_subnet => persister.cloud_subnets.lazy_find(x.properties.try(:subnet).try(:id)),
          :network_port => persister_network_port
        )

        persister.cloud_subnet_network_ports_secondary_index[uid] ||= x.properties.try(:private_ip_address)
      end
    end
  end

  def load_balancers
    collector.load_balancers.each do |lb|
      name = lb.name
      uid  = lb.id

      persister_load_balancer = persister.load_balancers.build(
        :ems_ref => uid,
        :name    => name,
      )

      load_balancer_listeners(persister_load_balancer, lb)
      load_balancer_network_port(persister_load_balancer, lb)
    end

    collector.load_balancers.each do |lb|
      # Depends on order, needs listeners computed first
      load_balancer_health_checks(persister.load_balancers.lazy_find(lb.id), lb)
    end
  end

  def load_balancer_pools(lb, pool_id)
    lb.properties["backendAddressPools"].each do |pool|
      uid = pool.id

      next unless pool_id == uid # TODO(lsmola) find more effective way

      persister_load_balancer_pool = persister.load_balancer_pools.build(
        :ems_ref => uid,
        :name    => pool.name,
      )

      load_balancer_pool_members(persister_load_balancer_pool, pool)
    end
  end

  def load_balancer_pool_members(persister_load_balancer_pool, pool)
    pool["properties"]["backendIPConfigurations"].to_a.each do |ipconfig|
      uid      = ipconfig.id
      nic_id   = uid.split("/")[0..-3].join("/") # Convert IpConfiguration id to networkInterfaces id

      persister_load_balancer_pool_member = persister.load_balancer_pool_members.build(
        :ems_ref => uid,
        :vm      => persister.network_ports.lazy_find(nic_id, :key => :device)
      )

      persister.load_balancer_pool_member_pools.build(
        :load_balancer_pool        => persister_load_balancer_pool,
        :load_balancer_pool_member => persister_load_balancer_pool_member
      )
    end
  end

  def load_balancer_listeners(persister_load_balancer, lb)
    lb.properties["loadBalancingRules"].each do |listener|
      uid           = listener["id"]
      pool_id       = listener.properties["backendAddressPool"]["id"]
      backend_port  = listener.properties["backendPort"].to_i
      frontend_port = listener.properties["frontendPort"].to_i

      persister_load_balancer_listener = persister.load_balancer_listeners.build(
        :ems_ref                  => uid,
        :load_balancer_protocol   => listener.properties["protocol"],
        :load_balancer_port_range => (backend_port..backend_port),
        :instance_protocol        => listener.properties["protocol"],
        :instance_port_range      => (frontend_port..frontend_port),
        :load_balancer            => persister_load_balancer,
      )

      persister.load_balancer_listener_pools.build(
        :load_balancer_listener => persister_load_balancer_listener,
        :load_balancer_pool     => persister.load_balancer_pools.lazy_find(pool_id)
      )

      load_balancer_pools(lb, pool_id)
    end
  end

  def load_balancer_network_port(persister_load_balancer, lb)
    uid = "#{lb.id}/nic1"

    persister.network_ports.build(
      :device_ref => lb.id,
      :device     => persister_load_balancer,
      :ems_ref    => uid,
      :name       => File.basename(lb.id) + '/nic1',
      :status     => "Succeeded",
      :source     => "refresh",
    )
  end

  def load_balancer_health_checks(persister_load_balancer, lb)
    # TODO(lsmola) think about adding members through listeners on model side, since copying deep nested relations of
    # members is not efficient

    # Index load_balancer_pool_member_pools by load_balancer_pool, so we can fetch members of each pool
    by_load_balancer_pool_member_pools = persister.load_balancer_pool_member_pools.data.each_with_object({}) do |x, obj|
      (obj[x[:load_balancer_pool].try(:[], :ems_ref)] ||= []) << x[:load_balancer_pool_member]
    end
    # Index load_balancer_pool by load_balancer_listener, so we can pools of each listener
    by_load_balancer_listeners = persister.load_balancer_listener_pools.data.each_with_object({}) do |x, obj|
      obj[x[:load_balancer_listener].try(:[], :ems_ref)] = x[:load_balancer_pool].try(:[], :ems_ref)
    end

    lb.properties["probes"].each do |health_check|
      uid = health_check.id

      load_balancing_rules = health_check.properties["loadBalancingRules"]
      # TODO(lsmola) Does Azure support multiple listeners per health check? If yes, the modeling of members through
      # listeners would need migration
      health_check_listener = persister.load_balancer_listeners.lazy_find(load_balancing_rules.first.id) if load_balancing_rules

      persister_load_balancer_health_check = persister.load_balancer_health_checks.build(
        :ems_ref                => uid,
        :protocol               => health_check.properties["protocol"],
        :port                   => health_check.properties["port"],
        :interval               => health_check.properties["intervalInSeconds"],
        :url_path               => health_check.properties["requestPath"],
        :load_balancer          => persister_load_balancer,
        :load_balancer_listener => health_check_listener,
      )

      next if load_balancing_rules.blank?

      # We will copy members of our listeners into health check members
      health_check_members = health_check
                             .properties["loadBalancingRules"]
                             .map { |x| by_load_balancer_listeners[x.id] }
                             .map { |x| by_load_balancer_pool_member_pools[x] }
                             .flatten

      health_check_members.compact.each do |health_check_member|
        persister.load_balancer_health_check_members.build(
          :load_balancer_health_check => persister_load_balancer_health_check,
          :load_balancer_pool_member  => health_check_member,
        )
      end
    end
  end

  def floating_ips
    collector.floating_ips.each do |ip|
      uid = ip.id

      # TODO(lsmola) get rid of all the find method that are ineffective, a lazy_find multi should solve it
      network_port_id = floating_ip_network_port_id(ip)

      network_port = persister.network_ports.find(network_port_id)
      if network_port
        vm = network_port.try(:[], :device)
      elsif persister.load_balancers.find(network_port_id)
        network_port = persister.network_ports.lazy_find("#{network_port_id}/nic1")
      end

      persister.floating_ips.build(
        :ems_ref          => uid,
        :status           => ip.properties.try(:provisioning_state),
        :address          => ip.properties.try(:ip_address) || ip.name,
        :network_port     => network_port,
        :fixed_ip_address => persister.cloud_subnet_network_ports_secondary_index[network_port_id],
        :vm               => vm
      )
    end
  end

  def calculate_source_ip_range(rule)
    if rule.properties.respond_to?(:source_address_prefix)
      rule.properties.source_address_prefix
    elsif rule.properties.respond_to?(:source_address_prefixes)
      rule.properties.source_address_prefixes.join(',')
    end
  end

  def calculate_start_port(rule)
    if rule.properties.respond_to?(:destination_port_range)
      rule.properties.destination_port_range.split('-').first.to_i
    elsif rule.properties.respond_to?(:destination_port_ranges)
      rule.properties.destination_port_ranges.flat_map { |e| e.split('-') }.map(&:to_i).min
    end
  end

  def calculate_end_port(rule)
    if rule.properties.respond_to?(:destination_port_range)
      rule.properties.destination_port_range.split('-').last.to_i
    elsif rule.properties.respond_to?(:destination_port_ranges)
      rule.properties.destination_port_ranges.flat_map { |e| e.split('-') }.map(&:to_i).max
    end
  end

  def floating_ip_network_port_id(ip)
    # TODO(lsmola) NetworkManager, we need to model ems_ref in model CloudSubnetNetworkPort and relate floating
    # ip to that model
    # For now cutting last 2 / from the id, to get just the id of the network_port. ID looks like:
    # /subscriptions/{guid}/resourceGroups/{resourceGroupName}/providers/Microsoft.Network/networkInterfaces/vm1nic1/ipConfigurations/ip1
    # where id of the network port is
    # /subscriptions/{guid}/resourceGroups/{resourceGroupName}/providers/Microsoft.Network/networkInterfaces/vm1nic1
    cloud_subnet_network_port_id = ip.properties.try(:ip_configuration).try(:id)
    cloud_subnet_network_port_id.split("/")[0..-3].join("/") if cloud_subnet_network_port_id
  end

  def resource_id_for_instance_id(id)
    # TODO(lsmola) we really need to get rid of the building our own emf_ref, it makes crosslinking impossible, parsing
    # the id string like this is suboptimal
    return nil unless id
    _, _, guid, _, resource_group, _, type, sub_type, name = id.split("/")
    File.join(guid, resource_group.downcase, type.downcase, sub_type.downcase, name)
  end
end
