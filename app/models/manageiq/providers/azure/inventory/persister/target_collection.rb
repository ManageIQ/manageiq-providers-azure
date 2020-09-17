class ManageIQ::Providers::Azure::Inventory::Persister::TargetCollection < ManageIQ::Providers::Azure::Inventory::Persister
  include ManageIQ::Providers::Azure::Inventory::Persister::Definitions::CloudCollections
  include ManageIQ::Providers::Azure::Inventory::Persister::Definitions::NetworkCollections

  def targeted?
    true
  end

  def strategy
    :local_db_find_missing_references
  end

  def parent
    if @init_network_collections
      manager.try(:network_manager)
    else
      manager.presence
    end
  end

  def initialize_inventory_collections
    initialize_tag_mapper
    initialize_cloud_inventory_collections

    @init_network_collections = true
    initialize_network_inventory_collections
    @init_network_collections = false
  end
end
