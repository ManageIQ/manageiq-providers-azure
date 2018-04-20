class ManageIQ::Providers::Azure::Inventory::Persister < ManagerRefresh::Inventory::Persister
  require_nested :CloudManager
  require_nested :NetworkManager
  require_nested :TargetCollection

  attr_reader :collector

  attr_reader :stack_resources_secondary_index, :cloud_subnet_network_ports_secondary_index

  # @param manager [ManageIQ::Providers::BaseManager] A manager object
  # @param target [Object] A refresh Target object
  # @param target [ManagerRefresh::Inventory::Collector] A Collector object
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

  def tag_mapper
    unless defined? @tag_mapper
      @tag_mapper = ContainerLabelTagMapping.mapper
      collections[:tags_to_resolve] = @tag_mapper.tags_to_resolve_collection
    end
    @tag_mapper
  end

  protected

  def cloud
    ManageIQ::Providers::Azure::InventoryCollectionDefault::CloudManager
  end

  def network
    ManageIQ::Providers::Azure::InventoryCollectionDefault::NetworkManager
  end

  def targeted
    false
  end

  def strategy
    nil
  end

  def shared_options
    settings_options = options[:inventory_collections].try(:to_hash) || {}

    settings_options.merge(
      :strategy => strategy,
      :targeted => targeted,
    )
  end
end
