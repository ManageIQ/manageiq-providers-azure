class ManageIQ::Providers::Azure::Inventory::Collector::NetworkManager < ManageIQ::Providers::Azure::Inventory::Collector
  def initialize(_manager, _target)
    super

    @rgs = resource_group_service(@config)
    @vns = virtual_network_service(@config)
    @ips = ip_address_service(@config)
    @nis = network_interface_service(@config)
    @nsg = network_security_group_service(@config)
    @lbs = load_balancer_service(@config)
  end

  def cloud_networks
    gather_data_for_this_region(@vns)
  end

  def security_groups
    gather_data_for_this_region(@nsg)
  end

  def network_ports
    network_interfaces
  end

  def load_balancers
    @load_balancers ||= gather_data_for_this_region(@lbs)
  end

  def floating_ips
    @floating_ips ||= gather_data_for_this_region(@ips)
  end
end
