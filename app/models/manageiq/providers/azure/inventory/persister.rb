class ManageIQ::Providers::Azure::Inventory::Persister < ManageIQ::Providers::Inventory::Persister
  require_nested :CloudManager
  require_nested :NetworkManager
  require_nested :TargetCollection

  attr_reader :collector

  attr_reader :stack_resources_secondary_index, :cloud_subnet_network_ports_secondary_index

  # @param manager [ManageIQ::Providers::BaseManager] A manager object
  # @param target [Object] A refresh Target object
  # @param collector [ManageIQ::Providers::Inventory::Collector] A Collector object
  def initialize(manager, target = nil, collector = nil)
    @manager   = manager
    @target    = target
    @collector = collector

    @collections = {}

    # TODO(lsmola) for release > g, we can use secondary indexes for this as
    @stack_resources_secondary_index            = {}
    @cloud_subnet_network_ports_secondary_index = {}

    initialize_inventory_collections
  end

  def initialize_inventory_collections
    initialize_tag_mapper
    initialize_cloud_inventory_collections
    initialize_network_inventory_collections
  end

  def initialize_cloud_inventory_collections
    %i(availability_zones
       disks
       flavors
       hardwares
       networks
       operating_systems
       resource_groups
       miq_templates
       vm_and_template_labels
       vm_and_template_taggings
       vms).each do |name|

      add_cloud_collection(name)
    end

    add_auth_key_pairs

    add_orchestration_stacks

    # slightly different from amazon
    %i(orchestration_stacks_resources
       orchestration_stacks_outputs
       orchestration_stacks_parameters
       orchestration_templates).each do |name|

      extra_properties = {:manager_ref => %i(stack ems_ref)} unless name == :orchestration_templates
      add_cloud_collection(name, extra_properties)
    end

    # Custom processing of Ancestry
    %i(vm_and_miq_template_ancestry
       orchestration_stack_ancestry).each do |name|

      add_cloud_collection(name)
    end
  end

  def initialize_network_inventory_collections
    %i(cloud_networks
       cloud_subnet_network_ports
       floating_ips
       network_ports
       network_routers
       load_balancers
       load_balancer_pools
       load_balancer_pool_members
       load_balancer_pool_member_pools
       load_balancer_listeners
       load_balancer_listener_pools
       load_balancer_health_checks
       load_balancer_health_check_members
       security_groups).each do |name|

      add_network_collection(name)
    end

    add_cloud_subnets

    add_firewall_rules
  end

  # ------ IC provider specific definitions -------------------------

  def add_auth_key_pairs(extra_properties = {})
    add_cloud_collection(:auth_key_pairs, extra_properties) do |builder|
      builder.add_properties(:model_class => ::ManageIQ::Providers::CloudManager::AuthKeyPair)
      builder.add_properties(:manager_uuids => name_references(:key_pairs)) if targeted?
    end
  end

  def add_orchestration_stacks
    add_cloud_collection(:orchestration_stacks) do |builder|
      builder.add_properties(:saver_strategy => 'default') # TODO(lsmola) can't batch unless we do smart batching
    end
  end

  # TODO: Builder params
  def add_cloud_subnets
    add_network_collection(:cloud_subnets, :default_values => nil) do |builder|
      builder.add_properties(:parent_inventory_collections => %i(cloud_networks))

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
    add_network_collection(:firewall_rules, extra_properties) do |builder|
      builder.add_properties(:manager_ref_allowed_nil => %i(source_security_group))
    end
  end

  private

  def case_sensitive_labels?
    false
  end
end
