module ManageIQ::Providers::Azure::Inventory::Persister::Definitions::NetworkCollections
  extend ActiveSupport::Concern

  def initialize_network_inventory_collections
    %i(cloud_networks
       security_groups
       load_balancers
       load_balancer_pools
       load_balancer_pool_members
       load_balancer_pool_member_pools
       load_balancer_listeners
       load_balancer_listener_pools
       load_balancer_health_checks
       load_balancer_health_check_members).each do |name|

      add_collection(network, name)
    end

    add_cloud_subnet_network_ports

    add_cloud_subnets # different in amazon

    add_firewall_rules

    add_floating_ips

    add_network_ports

    # Not in Amazon
    %i(network_routers).each do |name|
      add_collection(network, name)
    end
  end

  # ------ IC provider specific definitions -------------------------

  def add_cloud_subnet_network_ports
    add_collection(network, :cloud_subnet_network_ports)
  end

  def add_network_ports
    add_collection(network, :network_ports)
  end

  def add_floating_ips
    add_collection(network, :floating_ips)
  end

  # TODO: Different from amazon
  def add_cloud_subnets
    add_collection(network, :cloud_subnets) do |builder|
      builder.add_properties(:parent_inventory_collections => %i(cloud_networks))
      builder.add_properties(:builder_params => nil)

      builder.add_targeted_arel(
        lambda do |inventory_collection|
          manager_uuids = inventory_collection.parent_inventory_collections.flat_map { |c| c.manager_uuids.to_a }
          inventory_collection.parent.cloud_subnets.joins(:cloud_network).where(
            :cloud_networks => {:ems_ref => manager_uuids}
          )
        end
      )
    end
  end

  # TODO: Same as amazon?
  def add_firewall_rules(extra_properties = {})
    add_collection(network, :firewall_rules, extra_properties) do |builder|
      builder.add_properties(:manager_ref_allowed_nil => %i(source_security_group))
    end
  end
end
