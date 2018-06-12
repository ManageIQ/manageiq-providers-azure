class ManageIQ::Providers::Azure::Inventory::Persister::CloudManager < ManageIQ::Providers::Azure::Inventory::Persister
  include ManageIQ::Providers::Azure::Inventory::Persister::Definitions::CloudCollections

  def initialize_inventory_collections
    initialize_cloud_inventory_collections
  end
end
