class ManageIQ::Providers::Azure::Inventory::Persister::TargetCollection < ManageIQ::Providers::Azure::Inventory::Persister
  include ManageIQ::Providers::Azure::Inventory::Persister::Shared::CloudCollections
  include ManageIQ::Providers::Azure::Inventory::Persister::Shared::NetworkCollections

  def targeted?
    true
  end

  def strategy
    :local_db_find_missing_references
  end

  def initialize_inventory_collections
    initialize_cloud_inventory_collections

    initialize_network_inventory_collections
  end
end
