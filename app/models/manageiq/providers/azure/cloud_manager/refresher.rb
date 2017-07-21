module ManageIQ::Providers::Azure
  class CloudManager::Refresher < ManageIQ::Providers::BaseManager::Refresher
    include ::EmsRefresh::Refreshers::EmsRefresherMixin

    def collect_inventory_for_targets(ems, targets)
      log_header = format_ems_for_logging(ems)

      targets_with_data = targets.collect do |target|
        target_name = target.try(:name) || target.try(:event_type)

        _log.info "Collecting inventory for #{log_header}..."

        if refresher_options.try(:[], :inventory_object_refresh)
          inventory = ManageIQ::Providers::Azure::Builder.build_inventory(ems, target)
        end

        _log.info "#{log_header} - Collecting inventory...Complete"
        [target, inventory]
      end

      targets_with_data
    end

    def parse_targeted_inventory(ems, _target, inventory)
      log_header = format_ems_for_logging(ems)

      _log.info "#{log_header} Parsing inventory..."

      hashes, = Benchmark.realtime_block(:parse_inventory) do
        if refresher_options.try(:[], :inventory_object_refresh)
          inventory.inventory_collections
        else
          ManageIQ::Providers::Azure::CloudManager::RefreshParser.ems_inv_to_hashes(ems, refresher_options)
        end
      end

      hashes.each do |key, value|
        count = hashes[key].size
        _log.info "#{log_header} Parsed inventory for #{key.to_s.titleize}. Count: #{count}"
      end

      _log.info "Parsing inventory...Complete."

      hashes
    end

    def parse_legacy_inventory(ems)
      ManageIQ::Providers::Azure::CloudManager::RefreshParser.ems_inv_to_hashes(ems, refresher_options)
    end

    def save_inventory(ems, _targets, hashes)
      EmsRefresh.save_ems_inventory(ems, hashes)
      EmsRefresh.queue_refresh(ems.network_manager)
    end

    def post_process_refresh_classes
      [::Vm]
    end
  end
end
