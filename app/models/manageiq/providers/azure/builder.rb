class ManageIQ::Providers::Azure::Builder
  class << self
    def build_inventory(ems, target)
      case target
      when ManageIQ::Providers::Azure::CloudManager
        cloud_manager_inventory(ems, target)
      when ManageIQ::Providers::Azure::NetworkManager
        inventory(
          ems,
          target,
          ManageIQ::Providers::Azure::Inventory::Collector::NetworkManager,
          ManageIQ::Providers::Azure::Inventory::Persister::NetworkManager,
          [ManageIQ::Providers::Azure::Inventory::Parser::NetworkManager]
        )
      when ManagerRefresh::TargetCollection
        inventory(
          ems,
          target,
          ManageIQ::Providers::Azure::Inventory::Collector::TargetCollection,
          ManageIQ::Providers::Azure::Inventory::Persister::TargetCollection,
          [ManageIQ::Providers::Azure::Inventory::Parser::CloudManager,
           ManageIQ::Providers::Azure::Inventory::Parser::NetworkManager]
        )
      else
        # Fallback to ems refresh
        cloud_manager_inventory(ems, target)
      end
    end

    private

    def cloud_manager_inventory(ems, target)
      inventory(
        ems,
        target,
        ManageIQ::Providers::Azure::Inventory::Collector::CloudManager,
        ManageIQ::Providers::Azure::Inventory::Persister::CloudManager,
        [ManageIQ::Providers::Azure::Inventory::Parser::CloudManager]
      )
    end

    def inventory(manager, raw_target, collector_class, persister_class, parsers_classes)
      collector = collector_class.new(manager, raw_target)
      persister = persister_class.new(manager, raw_target, collector)

      ::ManageIQ::Providers::Azure::Inventory.new(
        persister,
        collector,
        parsers_classes.map(&:new)
      )
    end
  end
end
