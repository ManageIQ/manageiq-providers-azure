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
    refs = references(:resource_groups)

    return [] if refs.blank?

    if refs.size > record_limit
      set = Set.new(refs)
      collect_inventory(:resource_groups) { @resource_groups ||= @rgs.list(:all => true) }.select do |resource_group|
        set.include?(resource_group.id.downcase)
      end
    else
      collect_inventory(:resource_groups) do
        Parallel.map(refs, in_threads: thread_limit) do |ems_ref|
          @rgs.get(File.basename(ems_ref))
        end
      end
    end
  rescue ::Azure::Armrest::Exception => err
    _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
    []
  end

  def flavors
    refs = name_references(:flavors)

    return [] if refs.blank?
    set = Set.new(refs)

    collect_inventory(:series){ @vmm.series(@ems.provider_region) }.select do |flavor|
      set.include?(flavor.name.downcase)
    end
  rescue ::Azure::Armrest::Exception => err
    _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
    []
  end

  def availability_zones
    return [] if references(:availability_zones).blank?

    collect_inventory(:availability_zones) { [::Azure::Armrest::BaseModel.new(:name => @ems.name, :id => 'default')] }
  rescue ::Azure::Armrest::Exception => err
    _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
    []
  end

  def stacks
    refs = references(:orchestration_stacks)
    return [] if refs.blank?

    if refs.size > record_limit
      set = Set.new(refs)
      @stacks_cache ||= collect_inventory(:deployments) { gather_data_for_this_region(@tds, 'list') }.select do |stack|
        set.include?(stack.id)
      end
    else
      collect_inventory(:orchestration_stacks) do
        Parallel.map(refs, in_threads: thread_limit) do |ems_ref|
          @tds.get_by_id(ems_ref)
        end
      end
    end
  rescue ::Azure::Armrest::Exception => err
    _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
    []
  end

  def clear_stacks_cache!
    @stacks_cache = nil
  end

  def stack_resources(deployment)
    # Caching resources so we can scan then for edges, but only for targeted refresh
    @cached_resources ||= {}
    return @cached_resources[deployment.id] if @cached_resources[deployment.id]

    @cached_resources[deployment.id] = super
  end

  def instances
    refs = references(:vms)

    return [] if refs.blank?

    if refs.size > record_limit
      set = Set.new(refs)
      @instances_cache ||= collect_inventory(:instances) { gather_data_for_this_region(@vmm) }.select do |instance|
        uid = resource_uid(subscription_id,
                           instance.resource_group.downcase,
                           instance.type.downcase,
                           instance.name)

        set.include?(uid)
      end
    else
      Parallel.map(refs, in_threads: thread_limit) do |ems_ref|
        _subscription_id, group, _provider, _service, name = ems_ref.tr("\\", '/').split('/')
        @vmm.get(name, group)
      end
    end
  rescue ::Azure::Armrest::Exception => err
    _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
    []
  end

  def images
    refs = references(:miq_templates).select{ |ems_ref| ems_ref.start_with?('http') }
    return [] if refs.blank?

    set = Set.new(refs)

    collect_inventory(:private_images) { gather_data_for_this_region(@sas, 'list_all_private_images') }.select do |image|
      set.include?(image.uri)
    end
  rescue ::Azure::Armrest::Exception => err
    _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
    []
  end

  def managed_images
    refs = references(:miq_templates).reject{ |ems_ref| ems_ref.start_with?('http') }
    return [] if refs.blank?

    if refs.size > record_limit
      set = Set.new(refs)
      collect_inventory(:managed_images) { gather_data_for_this_region(@mis) }.select do |image|
        set.include?(image.id.downcase)
      end
    else
      collect_inventory(:managed_images) do
        Parallel.map(refs, in_threads: thread_limit) do |ems_ref|
          @mis.get_by_id(ems_ref)
        end
      end
    end
  rescue ::Azure::Armrest::Exception => err
    _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
    []
  end

  def market_images
    return [] if references(:miq_templates).blank?

    # TODO(lsmola) add filtered API
    urns = options.market_image_urns

    imgs = if urns
             urns.collect do |urn|
               publisher, offer, sku, version = urn.split(':')

               ::Azure::Armrest::VirtualMachineImage.new(
                 :location  => manager.provider_region,
                 :publisher => publisher,
                 :offer     => offer,
                 :sku       => sku,
                 :version   => version,
                 :id        => urn
               )
             end
           else
             gather_data_for_this_region(@vmis)
           end

    imgs.select do |image|
      references(:miq_templates).include?(image.id)
    end
  end

  ###########################################
  # API queries for NetworkManager
  ###########################################
  def cloud_networks
    return [] if references(:cloud_networks).blank?

    # TODO(lsmola) add filtered API
    gather_data_for_this_region(@vns).select do |cloud_network|
      references(:cloud_networks).include?(cloud_network.id)
    end
  end

  def security_groups
    return [] if references(:security_groups).blank?

    # TODO(lsmola) add filtered API
    gather_data_for_this_region(@nsg).select do |security_group|
      references(:security_groups).include?(security_group.id)
    end
  end

  def network_ports
    return [] if references(:network_ports).blank?

    # TODO(lsmola) add filtered API
    @network_ports_cache ||= network_interfaces.select do |network_port|
      references(:network_ports).include?(network_port.id)
    end
  end

  def load_balancers
    return [] if references(:load_balancers).blank?

    # TODO(lsmola) add filtered API
    @load_balancers ||= gather_data_for_this_region(@lbs).select do |load_balancer|
      references(:load_balancers).include?(load_balancer.id)
    end
  end

  def floating_ips
    return [] if references(:floating_ips).blank?

    # TODO(lsmola) add filtered API
    @floating_ips_cache ||= gather_data_for_this_region(@ips).select do |floating_ip|
      references(:floating_ips).include?(floating_ip.id)
    end
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
    # We have a list of stacks, vms, etc. collected from events. Now we want to look into our DB and API, and collect
    # ems_refs of every related object.
    if references(:orchestration_stacks).present?
      infer_related_stacks_ems_refs_api!
    end

    if references(:load_balancers).present?
      infer_related_lb_ems_refs_api!
    end

    if references(:vms).present?
      infer_related_vm_ems_refs_db!
      infer_related_vm_ems_refs_api!
    end

    if references(:network_ports).present?
      infer_related_network_port_ems_refs_db!
      infer_related_network_port_ems_refs_api!
    end

    if references(:cloud_networks).present?
      infer_related_cloud_network_ems_refs_db!
    end
  end

  def infer_related_lb_ems_refs_api!
    references(:load_balancers).each do |lb_ref|
      # We have artificially modeled network port for LB
      add_simple_target!(:network_ports, "#{lb_ref}/nic1")
    end

    load_balancers.each do |lb|
      next unless lb.properties.frontend_ip_configurations

      lb.properties.frontend_ip_configurations.each do |front_end_config|
        add_simple_target!(:floating_ips, front_end_config.try(:properties).try(:public_ip_address).try(:id))
      end
    end
  end

  def infer_related_stacks_ems_refs_api!
    # Get resource groups out of Stack references, we need them to fetch stacks
    references(:orchestration_stacks).each do |stack_ems_ref|
      resource_group_ems_ref = stack_ems_ref.split("/")[0..-5].join("/")
      add_simple_target!(:resource_groups, resource_group_ems_ref.downcase)
    end
    target.manager_refs_by_association_reset

    # Make depth configurable? Allows us to scan nested stacks up to depth.
    depth = 3
    nested = Set.new
    depth.times do
      new_nested = Set.new
      stacks.each do |stack|
        stack_resources(stack).each do |resource|
          if add_stack_resource_target(resource.properties.target_resource)
            new_nested << stack.id
          end
        end
      end

      # If there is no nested stack, we can break
      break if (new_nested - nested).blank?

      nested = new_nested
      # We need to clear stacks cache to process the new stack
      # TODO(lsmola) optimize to fetch just the new stack
      clear_stacks_cache!
      target.manager_refs_by_association_reset
    end

    # Reset the target cache, so we can access new targets inside
    target.manager_refs_by_association_reset
  end

  def add_stack_resource_target(resource)
    case resource.resource_type
    when "Microsoft.Compute/virtualMachines"
      add_simple_target!(:vms, resource_id_for_instance_id(resource.id))
    when "Microsoft.Network/loadBalancers"
      add_simple_target!(:load_balancers, resource.id)
    when "Microsoft.Network/networkInterfaces"
      add_simple_target!(:network_ports, resource.id)
    when "Microsoft.Network/publicIPAddresses"
      add_simple_target!(:floating_ips, resource.id)
    when "Microsoft.Network/virtualNetworks"
      add_simple_target!(:cloud_networks, resource.id)
    when "Microsoft.Resources/deployments"
      add_simple_target!(:orchestration_stacks, resource.id)
      return true
    end

    false
  end

  def infer_related_vm_ems_refs_db!
    changed_vms = manager.vms
                         .where(:ems_ref => references(:vms))
                         .includes(:key_pairs, :network_ports, :floating_ips, :orchestration_stack, :resource_group, :cloud_subnets => [:cloud_network])

    changed_vms.each do |vm|
      stack      = vm.orchestration_stack
      all_stacks = ([stack] + (stack.try(:ancestors) || [])).compact

      all_stacks.collect(&:ems_ref).compact.each { |ems_ref| add_simple_target!(:orchestration_stacks, ems_ref) }
      vm.cloud_networks.collect(&:ems_ref).compact.each { |ems_ref| add_simple_target!(:cloud_networks, ems_ref) }
      vm.floating_ips.collect(&:ems_ref).compact.each { |ems_ref| add_simple_target!(:floating_ips, ems_ref) }
      vm.network_ports.collect(&:ems_ref).compact.each do |ems_ref|
        # Add only real network ports, starting with "eni-"
        add_simple_target!(:network_ports, ems_ref) if ems_ref.start_with?("eni-")
      end
      vm.key_pairs.collect(&:name).compact.each do |name|
        target.add_target(:association => :key_pairs, :manager_ref => {:name => name})
      end

      add_simple_target!(:resource_groups, vm.resource_group.try(:ems_ref))
    end
  end

  def infer_related_vm_ems_refs_api!
    instances.each do |instance|
      # TODO(lsmola) add API scanning
      target.add_target(:association => :flavors, :manager_ref => {:name => instance.properties.hardware_profile.vm_size.downcase})
      add_simple_target!(:availability_zones, 'default')
      add_simple_target!(:resource_groups, get_resource_group_ems_ref(instance))
      instance.properties.network_profile.network_interfaces.collect(&:id).each do |network_port_ems_ref|
        add_simple_target!(:network_ports, network_port_ems_ref)
      end
    end

    # Reset the target cache, so we can access new targets inside
    target.manager_refs_by_association_reset
  end

  def infer_related_network_port_ems_refs_db!
    changed_network_ports = manager.network_ports
                                   .where(:ems_ref => references(:network_ports))
                                   .includes(:floating_ips, :cloud_subnets => [:cloud_network])

    changed_network_ports.each do |network_port|
      network_port.cloud_subnets.collect { |x| x.cloud_network.try(:ems_ref) }.compact.each { |ems_ref| add_simple_target!(:cloud_networks, ems_ref) }
      network_port.floating_ips.collect(&:ems_ref).compact.each { |ems_ref| add_simple_target!(:floating_ips, ems_ref) }
    end
  end

  def infer_related_network_port_ems_refs_api!
    network_ports.each do |network_port|
      add_simple_target!(:security_groups, network_port.properties.try(:network_security_group).try(:id))

      # We do not model subnets as top level collection for Azure, so we want to obtain only cloud_network
      subnets = network_port.properties.ip_configurations.map { |x| x.properties.try(:subnet).try(:id) }
      subnets.compact.map { |x| x.split("/")[0..-3].join("/") }.each do |cloud_network_ems_ref|
        add_simple_target!(:cloud_networks, cloud_network_ems_ref)
      end

      network_port.properties.ip_configurations.map { |x| x.properties.try(:public_ip_address).try(:id) }.each do |floating_ip_ems_ref|
        add_simple_target!(:floating_ips, floating_ip_ems_ref)
      end
    end

    # Reset the target cache, so we can access new targets inside
    target.manager_refs_by_association_reset
  end

  def infer_related_cloud_network_ems_refs_db!
    changed_cloud_networks = manager.cloud_networks
                                    .where(:ems_ref => references(:cloud_networks))
                                    .includes(:orchestration_stack)

    changed_cloud_networks.each do |cloud_network|
      add_simple_target!(:orchestration_stacks, cloud_network.orchestration_stack.try(:ems_ref))
    end
  end

  def add_simple_target!(association, ems_ref)
    return if ems_ref.blank?

    target.add_target(:association => association, :manager_ref => {:ems_ref => ems_ref})
  end

  # Compose an id string combining some existing keys
  def resource_uid(*keys)
    keys.join('\\')
  end

  def resource_id_for_instance_id(id)
    # TODO(lsmola) we really need to get rid of the building our own emf_ref, it makes crosslinking impossible, parsing
    # the id string like this is suboptimal
    return nil unless id
    _, _, guid, _, resource_group, _, type, sub_type, name = id.split("/")
    resource_uid(guid,
                 resource_group.downcase,
                 "#{type.downcase}/#{sub_type.downcase}",
                 name)
  end
end
