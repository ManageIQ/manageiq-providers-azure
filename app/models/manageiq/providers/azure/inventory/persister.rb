class ManageIQ::Providers::Azure::Inventory::Persister < ManageIQ::Providers::Inventory::Persister
  require_nested :CloudManager
  require_nested :NetworkManager
  require_nested :TargetCollection

  attr_reader :collector
  attr_reader :stack_resources_secondary_index, :cloud_subnet_network_ports_secondary_index

  def initialize_inventory_collections
    # TODO(lsmola) for release > g, we can use secondary indexes for this as
    @stack_resources_secondary_index            = {}
    @cloud_subnet_network_ports_secondary_index = {}

    initialize_cloud_inventory_collections
    initialize_network_inventory_collections
  end

  def initialize_cloud_inventory_collections
    add_cloud_collection(:availability_zones)
    add_cloud_collection(:disks)
    add_cloud_collection(:flavors)
    add_cloud_collection(:hardwares)
    add_cloud_collection(:networks)
    add_cloud_collection(:operating_systems)
    add_cloud_collection(:vm_and_template_labels)
    add_cloud_collection(:vm_and_template_taggings)
    add_cloud_collection(:vms)
    add_cloud_collection(:miq_templates) do |builder|
      builder.add_properties(:model_class => ::ManageIQ::Providers::Azure::CloudManager::Template)
      builder.add_default_values(:ems_id => manager.id, :vendor => builder.vendor)
    end
    add_cloud_collection(:key_pairs) do |builder|
      builder.add_properties(:model_class => ::ManageIQ::Providers::Azure::CloudManager::AuthKeyPair)
      builder.add_properties(:manager_uuids => name_references(:key_pairs)) if targeted?
    end
    add_cloud_collection(:resource_groups) do |builder|
      builder.add_properties(:model_class => ::ManageIQ::Providers::Azure::ResourceGroup)
      builder.add_default_values(:ems_id => manager.id)
    end
    add_cloud_collection(:orchestration_stacks) do |builder|
      builder.add_properties(:saver_strategy => 'default') # TODO(lsmola) can't batch unless we do smart batching
    end
    add_cloud_collection(:orchestration_stacks_resources, {:manager_ref => %i(stack ems_ref)})
    add_cloud_collection(:orchestration_stacks_outputs, {:manager_ref => %i(stack ems_ref)})
    add_cloud_collection(:orchestration_stacks_parameters, {:manager_ref => %i(stack ems_ref)})
    add_cloud_collection(:orchestration_templates)
    add_cloud_collection(:vm_and_miq_template_ancestry)
    add_cloud_collection(:orchestration_stack_ancestry)
  end

  def initialize_network_inventory_collections
    add_network_collection(:cloud_networks)
    add_network_collection(:cloud_subnet_network_ports)
    add_network_collection(:floating_ips)
    add_network_collection(:network_ports)
    add_network_collection(:network_routers)
    add_network_collection(:load_balancers)
    add_network_collection(:load_balancer_pools)
    add_network_collection(:load_balancer_pool_members)
    add_network_collection(:load_balancer_pool_member_pools)
    add_network_collection(:load_balancer_listeners)
    add_network_collection(:load_balancer_listener_pools)
    add_network_collection(:load_balancer_health_checks)
    add_network_collection(:load_balancer_health_check_members)
    add_network_collection(:security_groups)
    add_network_collection(:cloud_subnets, :default_values => nil) do |builder|
      builder.add_properties(:parent_inventory_collections => %i(cloud_networks))
      builder.add_targeted_arel(
        lambda do |inventory_collection|
          manager_uuids = inventory_collection.parent_inventory_collections.flat_map { |c| c.manager_uuids.to_a }
          inventory_collection.parent.cloud_subnets.joins(:cloud_network).where(:cloud_networks => {:ems_ref => manager_uuids})
        end
      )
    end
    add_network_collection(:firewall_rules) do |builder|
      builder.add_properties(:manager_ref_allowed_nil => %i(source_security_group))
    end
  end

  def add_cloud_collection(name, extra_properties = {}, settings = {})
    add_collection(cloud, name, extra_properties, settings) do |builder|
      builder.add_properties(:parent => cloud_manager)
      yield builder if block_given?
    end
  end

  def add_network_collection(name, extra_properties = {}, settings = {})
    add_collection(network, name, extra_properties, settings) do |builder|
      builder.add_properties(:parent => network_manager)
      yield builder if block_given?
    end
  end

  def cloud_manager
    manager.kind_of?(EmsCloud) ? manager : manager.parent_manager
  end

  def network_manager
    manager.kind_of?(EmsNetwork) ? manager : manager.network_manager
  end

  def tag_mapper
    unless defined? @tag_mapper
      @tag_mapper = ContainerLabelTagMapping.mapper
      collections[:tags_to_resolve] = @tag_mapper.tags_to_resolve_collection
    end
    @tag_mapper
  end
end
