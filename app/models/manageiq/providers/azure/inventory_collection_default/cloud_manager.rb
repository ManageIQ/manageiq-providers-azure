class ManageIQ::Providers::Azure::InventoryCollectionDefault::CloudManager < ManagerRefresh::InventoryCollectionDefault::CloudManager
  class << self
    def resource_groups(extra_attributes = {})
      attributes = {
        :model_class    => ::ManageIQ::Providers::Azure::ResourceGroup,
        :association    => :resource_groups,
        :builder_params => {
          :ems_id => ->(persister) { persister.manager.id },
        }
      }

      attributes.merge!(extra_attributes)
    end

    def vms(extra_attributes = {})
      attributes = {
        :model_class    => ::ManageIQ::Providers::Azure::CloudManager::Vm,
        :builder_params => {
          :ems_id => ->(persister) { persister.manager.id },
          :vendor => "azure",
        }
      }
      super(attributes.merge!(extra_attributes))
    end

    def miq_templates(extra_attributes = {})
      attributes = {
        :model_class    => ::ManageIQ::Providers::Azure::CloudManager::Template,
        :builder_params => {
          :ems_id   => ->(persister) { persister.manager.id },
          :vendor   => "azure",
          :template => true
        }
      }

      super(attributes.merge!(extra_attributes))
    end

    def availability_zones(extra_attributes = {})
      attributes = {
        :model_class => ::ManageIQ::Providers::Azure::CloudManager::AvailabilityZone,
      }

      super(attributes.merge!(extra_attributes))
    end

    def flavors(extra_attributes = {})
      attributes = {
        :model_class => ::ManageIQ::Providers::Azure::CloudManager::Flavor,
      }

      super(attributes.merge!(extra_attributes))
    end

    def key_pairs(extra_attributes = {})
      attributes = {
        :model_class => ::ManageIQ::Providers::Azure::CloudManager::AuthKeyPair,
      }

      super(attributes.merge!(extra_attributes))
    end

    def orchestration_stacks(extra_attributes = {})
      attributes = {
        :model_class => ::ManageIQ::Providers::Azure::CloudManager::OrchestrationStack,
      }

      super(attributes.merge!(extra_attributes))
    end

    def orchestration_stacks_resources(extra_attributes = {})
      attributes = {
        :manager_ref => %i(stack ems_ref)
      }

      super(attributes.merge!(extra_attributes))
    end

    def orchestration_stacks_outputs(extra_attributes = {})
      attributes = {
        :manager_ref => %i(stack ems_ref)
      }

      super(attributes.merge!(extra_attributes))
    end

    def orchestration_stacks_parameters(extra_attributes = {})
      attributes = {
        :manager_ref => %i(stack ems_ref)
      }

      super(attributes.merge!(extra_attributes))
    end

    def orchestration_templates(extra_attributes = {})
      attributes = {
        :model_class => ::ManageIQ::Providers::Azure::CloudManager::OrchestrationTemplate,
      }

      super(attributes.merge!(extra_attributes))
    end
  end
end
