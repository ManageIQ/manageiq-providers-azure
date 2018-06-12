module ManageIQ::Providers::Azure::Inventory::Persister::Definitions::CloudCollections
  extend ActiveSupport::Concern

  # TODO: almost same as amazon
  def initialize_cloud_inventory_collections
    %i(vms
       hardwares
       operating_systems
       networks
       disks
       availability_zones).each do |name|

      add_collection(cloud, name)
    end

    add_miq_templates

    add_flavors

    add_key_pairs

    add_resource_groups # not in amazon

    add_vm_and_template_labels

    add_vm_and_template_taggings

    add_orchestration_stacks

    # slightly different from amazon
    %i(orchestration_stacks_resources
       orchestration_stacks_outputs
       orchestration_stacks_parameters
       orchestration_templates).each do |name|

      extra_properties = {:manager_ref => %i(stack ems_ref)} unless name == :orchestration_templates
      add_collection(cloud, name, extra_properties)
    end

    # Custom processing of Ancestry
    add_vm_and_miq_template_ancestry

    add_orchestration_stack_ancestry
  end

  # ------ IC provider specific definitions -------------------------

  # TODO: Derive model class in core
  # Different from amazon
  def add_miq_templates
    add_collection(cloud, :miq_templates) do |builder|
      builder.add_properties(:model_class => ::ManageIQ::Providers::Azure::CloudManager::Template)

      builder.add_builder_params(
        :ems_id => manager.id,
        :vendor => builder.vendor
      )
    end
  end

  # Missing in amazon
  def add_resource_groups
    add_collection(cloud, :resource_groups, {}, {:auto_inventory_attributes => false}) do |builder|
      builder.add_properties(:model_class => ::ManageIQ::Providers::Azure::ResourceGroup)

      builder.add_builder_params(:ems_id => manager.id)
    end
  end

  # Targeted doesn't have special strategy like amazon
  def add_flavors
    add_collection(cloud, :flavors)
  end

  # TODO: almost same as amazon? (after targeted) - different model_class!
  # TODO: Derive model class in core
  def add_key_pairs(extra_properties = {})
    add_collection(cloud, :key_pairs, extra_properties) do |builder|
      builder.add_properties(:model_class => ::ManageIQ::Providers::Azure::CloudManager::AuthKeyPair)
      builder.add_properties(:manager_uuids => name_references(:key_pairs)) if targeted?
    end
  end

  # TODO: mslemr - parent model_class used anywhere? If not, should be deleted
  def add_orchestration_stacks
    add_collection(cloud, :orchestration_stacks) do |builder|
      builder.add_properties(
        :model_class    => ::ManageIQ::Providers::Azure::CloudManager::OrchestrationStack,
        :saver_strategy => 'default' # TODO(lsmola) can't batch unless we do smart batching
      )
    end
  end

  # TODO: mslemr - same as amazon!
  def add_vm_and_template_labels
    add_collection(cloud, :vm_and_template_labels) do |builder|
      builder.add_targeted_arel(
        lambda do |inventory_collection|
          manager_uuids = inventory_collection.parent_inventory_collections.collect(&:manager_uuids).map(&:to_a).flatten
          inventory_collection.parent.vm_and_template_labels.where(
            'vms' => {:ems_ref => manager_uuids}
          )
        end
      )
    end
  end

  # TODO: mslemr - same as amazon!
  def add_vm_and_template_taggings
    add_collection(cloud, :vm_and_template_taggings) do |builder|
      builder.add_properties(
        :model_class                  => Tagging,
        :manager_ref                  => %i(taggable tag),
        :parent_inventory_collections => %i(vms miq_templates)
      )

      builder.add_targeted_arel(
        lambda do |inventory_collection|
          manager_uuids = inventory_collection.parent_inventory_collections.collect(&:manager_uuids).map(&:to_a).flatten
          ems = inventory_collection.parent
          ems.vm_and_template_taggings.where(
            'taggable_id' => ems.vms_and_templates.where(:ems_ref => manager_uuids)
          )
        end
      )
    end
  end

  # TODO: mslemr - same as amazon!
  def add_vm_and_miq_template_ancestry
    add_collection(cloud, :vm_and_miq_template_ancestry, {}, {:auto_inventory_attributes => false, :auto_model_class => false, :without_model_class => true}) do |builder|
      builder.add_dependency_attributes(
        :vms           => [collections[:vms]],
        :miq_templates => [collections[:miq_templates]]
      )
    end
  end

  # TODO: mslemr - same as amazon!
  def add_orchestration_stack_ancestry
    add_collection(cloud, :orchestration_stack_ancestry, {}, {:auto_inventory_attributes => false, :auto_model_class => false, :without_model_class => true}) do |builder|
      builder.add_dependency_attributes(
        :orchestration_stacks           => [collections[:orchestration_stacks]],
        :orchestration_stacks_resources => [collections[:orchestration_stacks_resources]]
      )
    end
  end
end
