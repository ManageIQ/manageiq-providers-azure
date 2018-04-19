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

    def vm_and_template_labels(extra_attributes = {})
      attributes = {
        :model_class                  => CustomAttribute,
        :association                  => :vm_and_template_labels,
        :manager_ref                  => %i(resource name),
        :parent_inventory_collections => %i(vms miq_templates),
        :inventory_object_attributes  => %i(
          resource
          section
          name
          value
          source
        )
      }

      attributes[:targeted_arel] = lambda do |inventory_collection|
        manager_uuids = inventory_collection.parent_inventory_collections.collect(&:manager_uuids).map(&:to_a).flatten
        inventory_collection.parent.vm_and_template_labels.where(
          'vms' => {:ems_ref => manager_uuids}
        )
      end

      attributes.merge!(extra_attributes)
    end

    def vm_and_template_taggings(extra_attributes = {})
      attributes = {
        :model_class                  => Tagging,
        :association                  => :vm_and_template_taggings,
        :manager_ref                  => %i(taggable tag),
        :inventory_object_attributes  => %i(taggable tag),
        :parent_inventory_collections => %i(vms miq_templates),
      }

      attributes[:targeted_arel] = lambda do |inventory_collection|
        manager_uuids = inventory_collection.parent_inventory_collections.collect(&:manager_uuids).map(&:to_a).flatten
        ems = inventory_collection.parent
        ems.vm_and_template_taggings.where(
          'taggable_id' => ems.vms_and_templates.where(:ems_ref => manager_uuids)
        )
      end

      attributes.merge!(extra_attributes)
    end

    def orchestration_stacks(extra_attributes = {})
      attributes = {
        :model_class    => ::ManageIQ::Providers::Azure::CloudManager::OrchestrationStack,
        :saver_strategy => :default # TODO(lsmola) can't batch unless we do smart batching
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
