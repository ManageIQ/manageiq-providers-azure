class ManageIQ::Providers::Azure::Inventory::Persister < ManageIQ::Providers::Inventory::Persister
  require_nested :ContainerManager
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

  private

  def case_sensitive_labels?
    false
  end
end
