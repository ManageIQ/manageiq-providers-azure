module ManageIQ::Providers::Azure
  class CloudManager::Refresher < ManageIQ::Providers::BaseManager::ManagerRefresher
    def parse_legacy_inventory(ems)
      ManageIQ::Providers::Azure::CloudManager::RefreshParser.ems_inv_to_hashes(ems, refresher_options)
    end

    def save_inventory(ems, target, _hashes)
      super
      EmsRefresh.queue_refresh(ems.network_manager) if target.kind_of?(ManageIQ::Providers::BaseManager)
    end

    def preprocess_targets
      # sort the EMSes to be refreshed with cloud managers before other EMSes.
      # since @targets_by_ems_id is a hash, we have to insert the items into a new
      # hash in the order we want them to appear.
      sorted_ems_targets = {}
      # pull out the IDs of cloud managers and reinsert them in a new hash first, to take advantage of preserved insertion order
      cloud_manager_ids = @targets_by_ems_id.keys.select { |key| @ems_by_ems_id[key].kind_of? ManageIQ::Providers::Azure::CloudManager }
      cloud_manager_ids.each { |ems_id| sorted_ems_targets[ems_id] = @targets_by_ems_id.delete(ems_id) }
      # now that the cloud managers have been removed from @targets_by_ems_id, move the rest of the values
      # over to the new hash and then replace @targets_by_ems_id.
      @targets_by_ems_id.keys.each { |ems_id| sorted_ems_targets[ems_id] = @targets_by_ems_id.delete(ems_id) }
      @targets_by_ems_id = sorted_ems_targets

      super
    end

    def post_process_refresh_classes
      [::Vm]
    end
  end
end
