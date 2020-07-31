module ManageIQ::Providers::Azure::Inventory::Persister::Definitions::CloudCollections
  extend ActiveSupport::Concern

  def initialize_cloud_inventory_collections
    %i(availability_zones
       disks
       flavors
       hardwares
       networks
       operating_systems
       vm_and_template_labels
       vm_and_template_taggings
       vms).each do |name|

      add_collection(cloud, name)
    end

    add_miq_templates

    add_auth_key_pairs

    add_resource_groups

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
    %i(vm_and_miq_template_ancestry
       orchestration_stack_ancestry).each do |name|

      add_collection(cloud, name)
    end
  end

  # ------ IC provider specific definitions -------------------------

  def add_miq_templates
    add_collection(cloud, :miq_templates) do |builder|
      builder.add_properties(:model_class => ::ManageIQ::Providers::Azure::CloudManager::Template)

      builder.add_default_values(
        :ems_id => manager.id,
        :vendor => builder.vendor
      )
    end
  end

  def add_resource_groups
    add_collection(cloud, :resource_groups, {}, {:auto_inventory_attributes => false}) do |builder|
      builder.add_properties(:model_class => ::ManageIQ::Providers::Azure::ResourceGroup)
      builder.add_default_values(:ems_id => manager.id)
    end
  end

  def add_auth_key_pairs(extra_properties = {})
    add_collection(cloud, :auth_key_pairs, extra_properties) do |builder|
      builder.add_properties(:model_class => ::ManageIQ::Providers::CloudManager::AuthKeyPair)
      builder.add_properties(:manager_uuids => name_references(:key_pairs)) if targeted?
    end
  end

  def add_orchestration_stacks
    add_collection(cloud, :orchestration_stacks) do |builder|
      builder.add_properties(:saver_strategy => 'default') # TODO(lsmola) can't batch unless we do smart batching
    end
  end
end
