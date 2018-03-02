class ManageIQ::Providers::Azure::Inventory::Persister::NetworkManager < ManageIQ::Providers::Azure::Inventory::Persister
  def initialize_inventory_collections
    add_inventory_collections(
      network,
      %i(cloud_subnet_network_ports network_ports floating_ips cloud_subnets cloud_networks security_groups
         firewall_rules load_balancers load_balancer_pools load_balancer_pool_members load_balancer_pool_member_pools
         load_balancer_listeners load_balancer_listener_pools load_balancer_health_checks
         load_balancer_health_check_members)
    )

    add_inventory_collections(cloud,
                              %i(vms availability_zones),
                              :parent   => manager.parent_manager,
                              :strategy => :local_db_cache_all)
  end
end
