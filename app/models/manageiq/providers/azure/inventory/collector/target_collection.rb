class ManageIQ::Providers::Azure::Inventory::Collector::TargetCollection < ManageIQ::Providers::Azure::Inventory::Collector
  def initialize(_manager, _target)
    super

    @nis  = network_interface_service(@config)
    @ips  = ip_address_service(@config)
    @vmm  = virtual_machine_service(@config)
    @asm  = availability_set_service(@config)
    @tds  = template_deployment_service(@config)
    @rgs  = resource_group_service(@config)
    @sas  = storage_account_service(@config)
    @sds  = storage_disk_service(@config)
    @mis  = managed_image_service(@config)
    @vmis = virtual_machine_image_service(@config, :location => @ems.provider_region)

    @vns = virtual_network_service(@config)
    @nsg = network_security_group_service(@config)
    @lbs = load_balancer_service(@config)

    parse_targets!
    infer_related_ems_refs!

    # Reset the target cache, so we can access new targets inside
    target.manager_refs_by_association_reset
  end

  ###########################################
  # API queries for CloudManager
  ###########################################
  def resource_groups
    return [] if references(:resource_groups).blank?

    # TODO(lsmola) add filtered API
  end

  def flavors
    return [] if references(:flavors).blank?

    # TODO(lsmola) add filtered API
  end

  def availability_zones
    return [] if references(:availability_zones).blank?

    # TODO(lsmola) add filtered API
  end

  def stacks
    return [] if references(:orchestration_stacks).blank?

    # TODO(lsmola) add filtered API
  end

  def stack_templates
    return [] if references(:orchestration_templates).blank?

    # TODO(lsmola) add filtered API
  end

  def instances
    return [] if references(:vms).blank?

    # TODO(lsmola) add filtered API
  end

  def images
    return [] if references(:miq_templates).blank?

    # TODO(lsmola) add filtered API
  end

  def managed_images
    return [] if references(:miq_templates).blank?

    # TODO(lsmola) add filtered API
  end

  def market_images
    return [] if references(:miq_templates).blank?

    # TODO(lsmola) add filtered API
  end

  ###########################################
  # API queries for NetworkManager
  ###########################################
  def cloud_networks
    return [] if references(:cloud_networks).blank?

    # TODO(lsmola) add filtered API
  end

  def security_groups
    return [] if references(:security_groups).blank?

    # TODO(lsmola) add filtered API
  end

  def network_ports
    return [] if references(:network_ports).blank?

    # TODO(lsmola) add filtered API
  end

  def load_balancers
    return [] if references(:load_balancers).blank?

    # TODO(lsmola) add filtered API
  end

  def floating_ips
    return [] if references(:floating_ips).blank?

    # TODO(lsmola) add filtered API
  end

  ###########################################
  # Helper method for getting references
  ###########################################
  def references(collection)
    target.manager_refs_by_association.try(:[], collection).try(:[], :ems_ref).try(:to_a).try(:compact) || []
  end

  def name_references(collection)
    target.manager_refs_by_association.try(:[], collection).try(:[], :name).try(:to_a).try(:compact) || []
  end

  private

  def parse_targets!
    target.targets.each do |t|
      case t
      when Vm
        parse_vm_target!(t)
      end
    end
  end

  def parse_vm_target!(t)
    add_simple_target!(:vms, t.ems_ref)
  end

  def infer_related_ems_refs!
    # We have a list of instances_refs collected from events. Now we want to look into our DB and API, and collect
    # ems_refs of every related object. Now this is not very nice fro ma design point of view, but we really want
    # to see changes in VM's associated objects, so the VM view is always consistent and have fresh data. The partial
    # reason for this is, that AWS doesn't send all the objects state change,
    if references(:vms).present?
      infer_related_vm_ems_refs_db!
      infer_related_vm_ems_refs_api!
    end
  end

  def infer_related_vm_ems_refs_db!
    changed_vms = manager.vms.where(:ems_ref => references(:vms)).includes(:key_pairs, :network_ports, :floating_ips,
                                                                           :orchestration_stack, :cloud_subnets)
    changed_vms.each do |vm|
      stack      = vm.orchestration_stack
      all_stacks = ([stack] + (stack.try(:ancestors) || [])).compact

      all_stacks.collect(&:ems_ref).compact.each { |ems_ref| add_simple_target!(:orchestration_stacks, ems_ref) }
      vm.cloud_subnets.collect(&:ems_ref).compact.each { |ems_ref| add_simple_target!(:cloud_subnets, ems_ref) }
      vm.floating_ips.collect(&:ems_ref).compact.each { |ems_ref| add_simple_target!(:floating_ips, ems_ref) }
      vm.network_ports.collect(&:ems_ref).compact.each do |ems_ref|
        # Add only real network ports, starting with "eni-"
        add_simple_target!(:network_ports, ems_ref) if ems_ref.start_with?("eni-")
      end
      vm.key_pairs.collect(&:name).compact.each do |name|
        target.add_target(:association => :key_pairs, :manager_ref => {:name => name})
      end
    end
  end

  def infer_related_vm_ems_refs_api!
    instances.each do |vm|
      # TODO(lsmola) add API scanning
      # add_simple_target!(:miq_templates, vm["image_id"])
    end

    # Reset the target cache, so we can access new targets inside
    target.manager_refs_by_association_reset
  end

  def add_simple_target!(association, ems_ref)
    return if ems_ref.blank?

    target.add_target(:association => association, :manager_ref => {:ems_ref => ems_ref})
  end
end
