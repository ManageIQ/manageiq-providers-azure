class ManageIQ::Providers::Azure::InventoryCollectionDefault::NetworkManager < ManagerRefresh::InventoryCollectionDefault::NetworkManager
  class << self
    def network_ports(extra_attributes = {})
      attributes = {
        :model_class => ::ManageIQ::Providers::Azure::NetworkManager::NetworkPort,
      }

      super(attributes.merge!(extra_attributes))
    end

    def floating_ips(extra_attributes = {})
      attributes = {
        :model_class => ::ManageIQ::Providers::Azure::NetworkManager::FloatingIp,
      }

      super(attributes.merge!(extra_attributes))
    end

    def cloud_subnets(extra_attributes = {})
      attributes = {
        :model_class                  => ::ManageIQ::Providers::Azure::NetworkManager::CloudSubnet,
        :parent_inventory_collections => [:cloud_networks],
      }

      extra_attributes[:targeted_arel] = lambda do |inventory_collection|
        manager_uuids = inventory_collection.parent_inventory_collections.flat_map { |c| c.manager_uuids.to_a }
        inventory_collection.parent.cloud_subnets.joins(:cloud_network).where(
          :cloud_network => {:ems_ref => manager_uuids}
        )
      end

      super(attributes.merge!(extra_attributes))
    end

    def cloud_networks(extra_attributes = {})
      attributes = {
        :model_class => ::ManageIQ::Providers::Azure::NetworkManager::CloudNetwork,
      }

      super(attributes.merge!(extra_attributes))
    end

    def security_groups(extra_attributes = {})
      attributes = {
        :model_class => ::ManageIQ::Providers::Azure::NetworkManager::SecurityGroup,
      }

      super(attributes.merge!(extra_attributes))
    end

    def firewall_rules(extra_attributes = {})
      attributes = {
        :manager_ref_allowed_nil => [:source_security_group],
      }

      super(attributes.merge!(extra_attributes))
    end

    def load_balancers(extra_attributes = {})
      attributes = {
        :model_class => ::ManageIQ::Providers::Azure::NetworkManager::LoadBalancer,
      }

      super(attributes.merge!(extra_attributes))
    end

    def load_balancer_pools(extra_attributes = {})
      attributes = {
        :model_class => ::ManageIQ::Providers::Azure::NetworkManager::LoadBalancerPool,
      }

      super(attributes.merge!(extra_attributes))
    end

    def load_balancer_pool_members(extra_attributes = {})
      attributes = {
        :model_class => ::ManageIQ::Providers::Azure::NetworkManager::LoadBalancerPoolMember,
      }

      super(attributes.merge!(extra_attributes))
    end

    def load_balancer_listeners(extra_attributes = {})
      attributes = {
        :model_class => ::ManageIQ::Providers::Azure::NetworkManager::LoadBalancerListener,
      }

      super(attributes.merge!(extra_attributes))
    end

    def load_balancer_health_checks(extra_attributes = {})
      attributes = {
        :model_class => ::ManageIQ::Providers::Azure::NetworkManager::LoadBalancerHealthCheck,
      }

      super(attributes.merge!(extra_attributes))
    end
  end
end
