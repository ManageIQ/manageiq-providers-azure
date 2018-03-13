class ManageIQ::Providers::Azure::Inventory::Collector::NetworkManager < ManageIQ::Providers::Azure::Inventory::Collector
  def cloud_networks
    gather_data_for_this_region(@vns)
  end

  def security_groups
    gather_data_for_this_region(@nsg)
  end

  def load_balancers
    @load_balancers ||= gather_data_for_this_region(@lbs)
  end

  def network_routers
    @network_routers = gather_data_for_this_region(@rts)
  end
end
