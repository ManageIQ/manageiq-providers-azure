class ManageIQ::Providers::Azure::Inventory::Persister::TargetCollection < ManageIQ::Providers::Azure::Inventory::Persister
  def targeted?
    true
  end

  def strategy
    :local_db_find_missing_references
  end
end
