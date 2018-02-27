class ManageIQ::Providers::Azure::Inventory::Parser::NetworkManager < ManageIQ::Providers::Azure::Inventory::Parser
  def parse
    log_header = "Collecting data for EMS : [#{collector.manager.name}] id: [#{collector.manager.id}]"

    @data_index = {}

    _log.info("#{log_header}...")

    security_groups
    cloud_networks
    network_ports
    load_balancers
    floating_ips

    _log.info("#{log_header}...Complete")
  end

  private

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
          ManagerRefresh::ApplicationRecordReference.new(OrchestrationStack, resource.stack_id)
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
      )
    end
  end

  def network_ports
    collector.network_ports.each do |network_port|
      uid = network_port.id

      # TODO(lsmola) solve with secondary index for version > g
      network_port.properties.ip_configurations.each do |ipconfig|
        persister.network_port_secondary_index[ipconfig.id] = uid
      end

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

      load_balancer_pools(lb)
      load_balancer_listeners(persister_load_balancer, lb)
      load_balancer_network_port(persister_load_balancer, lb)
    end

    collector.load_balancers.each do |lb|
      # Depends on order, needs listeners computed first
      load_balancer_health_checks(persister.load_balancers.lazy_find(lb.id), lb)
    end
  end

  def load_balancer_pools(lb)
    lb.properties["backendAddressPools"].each do |pool|
      uid = pool.id

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
      nic_id   = persister.network_port_secondary_index[uid]
      net_port = persister.network_ports.find(nic_id)

      next unless net_port && net_port[:device]

      persister_load_balancer_pool_member = persister.load_balancer_pool_members.build(
        :ems_ref => uid,
        :vm      => net_port[:device]
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
        :ems_ref                      => uid,
        :load_balancer_protocol       => listener.properties["protocol"],
        :load_balancer_port_range     => (backend_port..backend_port),
        :instance_protocol            => listener.properties["protocol"],
        :instance_port_range          => (frontend_port..frontend_port),
        :load_balancer                => persister_load_balancer,
      )

      persister.load_balancer_listener_pools.build(
        :load_balancer_listener => persister_load_balancer_listener,
        :load_balancer_pool     => persister.load_balancer_pools.lazy_find(pool_id)
      )
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
    else
      nil # Old api-version
    end
  end

  def calculate_start_port(rule)
    if rule.properties.respond_to?(:destination_port_range)
      rule.properties.destination_port_range.split('-').first.to_i
    elsif rule.properties.respond_to?(:destination_port_ranges)
      rule.properties.destination_port_ranges.flat_map { |e| e.split('-') }.map(&:to_i).min
    else
      nil # Old api-version
    end
  end

  def calculate_end_port(rule)
    if rule.properties.respond_to?(:destination_port_range)
      rule.properties.destination_port_range.split('-').last.to_i
    elsif rule.properties.respond_to?(:destination_port_ranges)
      rule.properties.destination_port_ranges.flat_map { |e| e.split('-') }.map(&:to_i).max
    else
      nil # Old api-version
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
    resource_uid(guid,
      resource_group.downcase,
      "#{type.downcase}/#{sub_type.downcase}",
      name
    )
  end
end
