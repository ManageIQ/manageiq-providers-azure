class ManageIQ::Providers::Azure::Inventory::Collector::TargetCollection < ManageIQ::Providers::Azure::Inventory::Collector
  def initialize(_manager, _target)
    super

    @targeted_stacks_cache = {}

    parse_targets!
    infer_related_ems_refs!

    # Reset the target cache, so we can access new targets inside
    target.manager_refs_by_association_reset

    # Do instances advanced caching
    instances_power_state_advanced_caching(instances)
  end

  ###########################################
  # API queries for CloudManager
  ###########################################
  def resource_groups
    refs = references(:resource_groups)

    return [] if refs.blank?

    refs = refs.map { |x| File.basename(x) }.uniq

    @resource_groups ||= if refs.size > record_limit
                           set = Set.new(refs)
                           collect_inventory(:resource_groups) { @rgs.list(:all => true) }.select do |resource_group|
                             set.include?(File.basename(resource_group.id.downcase))
                           end
                         else
                           collect_inventory_targeted(:resource_groups) do
                             Parallel.map(refs, :in_threads => thread_limit) do |ref|
                               safe_targeted_request { @rgs.get(ref) }
                             end
                           end
                         end
  rescue ::Azure::Armrest::Exception => err
    _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
    []
  end

  def network_routers
    [] # TODO: add targeted refresh
  end

  def flavors
    refs = references(:flavors)
    return [] if refs.blank?

    @flavors ||= begin
      set = Set.new(refs)

      collect_inventory_targeted(:series) { @vmm.series(@ems.provider_region) }.select do |flavor|
        set.include?(flavor.name.downcase) # ems_ref is downcased flavor name
      end
    rescue ::Azure::Armrest::Exception => err
      _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
      []
    end
  end

  def availability_zones
    return [] if references(:availability_zones).blank?

    collect_inventory_targeted(:availability_zones) { [::Azure::Armrest::BaseModel.new(:name => @ems.name, :id => 'default')] }
  rescue ::Azure::Armrest::Exception => err
    _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
    []
  end

  def stacks
    refs = references(:orchestration_stacks)
    return [] if refs.blank?

    if refs.size > record_limit
      set = Set.new(refs)

      @stacks_cache ||= super
      @subset_of_stacks_cache ||= @stacks_cache.select { |stack| set.include?(stack.id) }
    else
      not_fetched_refs = refs - targeted_stacks_cache.keys

      if not_fetched_refs.present?
        current_stacks = collect_inventory_targeted(:deployments) do
          Parallel.map(not_fetched_refs, :in_threads => thread_limit) do |ems_ref|
            safe_targeted_request { @tds.get_by_id(ems_ref) }
          end
        end

        current_stacks.each do |stack|
          targeted_stacks_cache[stack.id] = stack
        end

        stacks_advanced_caching(current_stacks, not_fetched_refs)
      end

      refs.map { |x| targeted_stacks_cache[x] }.compact
    end
  rescue ::Azure::Armrest::Exception => err
    _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
    []
  end

  def clear_stacks_cache!
    @subset_of_stacks_cache = nil
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

    @instances_cache ||= if refs.size > record_limit
                           set = Set.new(refs)
                           collect_inventory(:instances) { gather_data_for_this_region(@vmm) }.select do |instance|
                             uid = File.join(subscription_id,
                                             instance.resource_group.downcase,
                                             instance.type.downcase,
                                             instance.name)

                             set.include?(uid)
                           end
                         else
                           collect_inventory_targeted(:instances) do
                             Parallel.map(refs, :in_threads => thread_limit) do |ems_ref|
                               _subscription_id, group, _provider, _service, name = ems_ref.split('/')
                               safe_targeted_request { @vmm.get(name, group) }
                             end
                           end
                         end
  rescue ::Azure::Armrest::Exception => err
    _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
    []
  end

  def managed_disks
    refs = references(:managed_disks)

    return [] if refs.blank?

    @managed_disks ||= if refs.size > record_limit
                         set = Set.new(refs)
                         super.select do |managed_disk|
                           set.include?(managed_disk.id)
                         end
                       else
                         collect_inventory_targeted(:managed_disks) do
                           Parallel.map(refs, :in_threads => thread_limit) do |ems_ref|
                             safe_targeted_request { @sds.get_by_id(ems_ref) }
                           end
                         end
                       end
  rescue ::Azure::Armrest::Exception => err
    _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
    []
  end

  def storage_accounts
    refs = references(:storage_accounts)

    return [] if refs.blank?

    @storage_accounts ||= if refs.size > record_limit
                            super # This is already filtered to used storage_accounts only in full refresh
                          else
                            collect_inventory_targeted(:storage_accounts) do
                              Parallel.map(refs, :in_threads => thread_limit) do |ems_ref|
                                arr            = ems_ref.split("/")
                                resource_group = arr[-2] # get method just takes resource group name
                                storage_acc    = arr[-1]

                                safe_targeted_request { @sas.get(storage_acc, resource_group) }
                              end
                            end
                          end
  rescue ::Azure::Armrest::Exception => err
    _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
    []
  end

  def images
    refs = references(:miq_templates).select { |ems_ref| ems_ref.start_with?('http') }
    return [] if refs.blank?

    set = Set.new(refs)

    collect_inventory_targeted(:private_images) { gather_data_for_this_region(@sas, 'list_all_private_images') }.select do |image|
      set.include?(image.uri)
    end
  rescue ::Azure::Armrest::Exception => err
    _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
    []
  end

  def managed_images
    refs = references(:miq_templates).reject { |ems_ref| ems_ref.start_with?('http') }
    return [] if refs.blank?

    if refs.size > record_limit
      set = Set.new(refs)
      collect_inventory(:managed_images) { gather_data_for_this_region(@mis) }.select do |image|
        set.include?(image.id.downcase)
      end
    else
      collect_inventory_targeted(:managed_images) do
        Parallel.map(refs, :in_threads => thread_limit) do |ems_ref|
          safe_targeted_request { @mis.get_by_id(ems_ref) }
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

    imgs = collect_inventory_targeted(:market_images) do
      if urns
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
    end

    imgs.select do |image|
      references(:miq_templates).include?(image.id)
    end
  end

  def mariadb_servers
    []
  end

  def mariadb_databases
    []
  end

  def mysql_servers
    []
  end

  def mysql_databases
    []
  end

  def postgresql_servers
    []
  end

  def postgresql_databases
    []
  end

  def sql_servers
    []
  end

  def sql_databases
    []
  end

  ###########################################
  # API queries for NetworkManager
  ###########################################
  def cloud_networks
    refs = references(:cloud_networks)
    return [] if refs.blank?

    if refs.size > record_limit
      set = Set.new(refs)
      collect_inventory(:cloud_networks) { gather_data_for_this_region(@vns) }.select do |cloud_network|
        set.include?(cloud_network.id)
      end
    else
      collect_inventory_targeted(:cloud_networks) do
        Parallel.map(refs, :in_threads => thread_limit) do |ems_ref|
          safe_targeted_request { @vns.get_by_id(ems_ref) }
        end
      end
    end
  rescue ::Azure::Armrest::Exception => err
    _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
    []
  end

  def security_groups
    refs = references(:security_groups)
    return [] if refs.blank?

    if refs.size > record_limit
      set = Set.new(refs)
      collect_inventory(:security_groups) { gather_data_for_this_region(@nsg) }.select do |security_group|
        set.include?(security_group.id)
      end
    else
      collect_inventory_targeted(:security_groups) do
        Parallel.map(refs, :in_threads => thread_limit) do |ems_ref|
          safe_targeted_request { @nsg.get_by_id(ems_ref) }
        end
      end
    end
  rescue ::Azure::Armrest::Exception => err
    _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
    []
  end

  def network_ports
    refs = references(:network_ports)
    return [] if refs.blank?

    @network_ports_cache ||= if refs.size > record_limit
                               set = Set.new(refs)
                               collect_inventory(:network_ports) { @network_ports_cache ||= get_network_interfaces }.select do |network_port|
                                 set.include?(network_port.id)
                               end
                             else
                               refs = refs.select { |ems_ref| ems_ref =~ /networkinterfaces/i }
                               collect_inventory_targeted(:network_ports) do
                                 Parallel.map(refs, :in_threads => thread_limit) do |ems_ref|
                                   safe_targeted_request { @nis.get_by_id(ems_ref) }
                                 end
                               end
                             end
  rescue ::Azure::Armrest::Exception => err
    _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
    []
  end

  def load_balancers
    refs = references(:load_balancers)
    return [] if refs.blank?

    @load_balancers_cache ||= if refs.size > record_limit
                                set = Set.new(refs)
                                collect_inventory(:load_balancers) { @load_balancers ||= gather_data_for_this_region(@lbs) }.select do |load_balancer|
                                  set.include?(load_balancer.id)
                                end
                              else
                                collect_inventory_targeted(:load_balancers) do
                                  Parallel.map(refs, :in_threads => thread_limit) do |ems_ref|
                                    safe_targeted_request { @lbs.get_by_id(ems_ref) }
                                  end
                                end
                              end
  rescue ::Azure::Armrest::Exception => err
    _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
    []
  end

  def floating_ips
    refs = references(:floating_ips)
    return [] if refs.blank?

    @floating_ips_cache ||= if refs.size > record_limit
                              set = Set.new(refs)
                              collect_inventory(:floating_ips) { @floating_ips_cache ||= gather_data_for_this_region(@ips) }.select do |floating_ip|
                                set.include?(floating_ip.id)
                              end
                            else
                              collect_inventory_targeted(:floating_ips) do
                                Parallel.map(refs, :in_threads => thread_limit) do |ems_ref|
                                  safe_targeted_request { @ips.get_by_id(ems_ref) }
                                end
                              end
                            end
  rescue ::Azure::Armrest::Exception => err
    _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
    []
  end

  private

  attr_accessor :targeted_stacks_cache

  def parse_targets!
    target.targets.each do |t|
      case t
      when Vm
        add_target!(:vms, t.ems_ref)
      end
    end
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
      add_target!(:network_ports, "#{lb_ref}/nic1")
    end

    load_balancers.each do |lb|
      next unless lb.properties.frontend_ip_configurations

      lb.properties.frontend_ip_configurations.each do |front_end_config|
        add_target!(:floating_ips, front_end_config.try(:properties).try(:public_ip_address).try(:id))
      end
    end
  end

  def infer_related_stacks_ems_refs_api!
    # Get resource groups out of Stack references, we need them to fetch stacks
    references(:orchestration_stacks).each do |stack_ems_ref|
      resource_group_ems_ref = stack_ems_ref.split("/")[0..4].join("/")
      add_target!(:resource_groups, resource_group_ems_ref.downcase)
    end
    target.manager_refs_by_association_reset

    # Make depth configurable? Allows us to scan nested stacks up to depth.
    depth = 3
    nested = Set.new
    depth.times do
      new_nested = Set.new
      stacks.each do |stack|
        if (resources = stacks_resources_cache[stack.id])
          # If the stack hasn't changed, we load existing resources in batches from our DB, this saves a lot of time
          # comparing to doing API query for resources per each stack
          resources.each do |x|
            if add_stack_resource_target(OpenStruct.new(:id => x[:ems_ref], :resource_type => x[:resource_category]))
              new_nested << stack.id
            end
          end
        else
          stack_resources(stack).each do |resource|
            if add_stack_resource_target(resource.properties.target_resource)
              new_nested << stack.id
            end
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
      add_target!(:vms, resource_id_for_instance_id(resource.id))
    when "Microsoft.Network/loadBalancers"
      add_target!(:load_balancers, resource.id)
    when "Microsoft.Network/networkInterfaces"
      add_target!(:network_ports, resource.id)
    when "Microsoft.Network/publicIPAddresses"
      add_target!(:floating_ips, resource.id)
    when "Microsoft.Network/virtualNetworks"
      add_target!(:cloud_networks, resource.id)
    when "Microsoft.Resources/deployments"
      add_target!(:orchestration_stacks, resource.id)
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

      all_stacks.collect(&:ems_ref).compact.each { |ems_ref| add_target!(:orchestration_stacks, ems_ref) }
      vm.cloud_networks.collect(&:ems_ref).compact.each { |ems_ref| add_target!(:cloud_networks, ems_ref) }
      vm.floating_ips.collect(&:ems_ref).compact.each { |ems_ref| add_target!(:floating_ips, ems_ref) }
      vm.network_ports.collect(&:ems_ref).compact.each do |ems_ref|
        # Add only real network ports, starting with "eni-"
        add_target!(:network_ports, ems_ref) if ems_ref.start_with?("eni-")
      end
      vm.key_pairs.collect(&:name).compact.each do |name|
        target.add_target(:association => :key_pairs, :manager_ref => {:name => name})
      end

      add_target!(:resource_groups, vm.resource_group.try(:ems_ref))
    end
  end

  def infer_related_vm_ems_refs_api!
    instances.each do |instance|
      # TODO(lsmola) add API scanning
      target.add_target(:association => :flavors, :manager_ref => {:ems_ref => instance.properties.hardware_profile.vm_size.downcase})
      add_target!(:availability_zones, 'default')
      add_target!(:resource_groups, get_resource_group_ems_ref(instance))
      instance.properties.network_profile.network_interfaces.collect(&:id).each do |network_port_ems_ref|
        add_target!(:network_ports, network_port_ems_ref)
      end

      disks = instance.properties.storage_profile.data_disks + [instance.properties.storage_profile.os_disk]
      disks.each do |disk|
        if instance.managed_disk?
          add_target!(:managed_disks, disk.managed_disk.id)
        else
          disk_location = disk.try(:vhd).try(:uri)
          if disk_location
            uri = Addressable::URI.parse(disk_location)
            storage_name = uri.host.split('.').first

            add_target!(:storage_accounts, "#{get_resource_group_ems_ref(instance)}/#{storage_name}")
          end
        end
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
      network_port.cloud_subnets.collect { |x| x.cloud_network.try(:ems_ref) }.compact.each { |ems_ref| add_target!(:cloud_networks, ems_ref) }
      network_port.floating_ips.collect(&:ems_ref).compact.each { |ems_ref| add_target!(:floating_ips, ems_ref) }
    end
  end

  def infer_related_network_port_ems_refs_api!
    network_ports.each do |network_port|
      add_target!(:security_groups, network_port.properties.try(:network_security_group).try(:id))

      # We do not model subnets as top level collection for Azure, so we want to obtain only cloud_network
      subnets = network_port.properties.ip_configurations.map { |x| x.properties.try(:subnet).try(:id) }
      subnets.compact.map { |x| x.split("/")[0..-3].join("/") }.each do |cloud_network_ems_ref|
        add_target!(:cloud_networks, cloud_network_ems_ref)
      end

      network_port.properties.ip_configurations.map { |x| x.properties.try(:public_ip_address).try(:id) }.each do |floating_ip_ems_ref|
        add_target!(:floating_ips, floating_ip_ems_ref)
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
      add_target!(:orchestration_stacks, cloud_network.orchestration_stack.try(:ems_ref))
    end
  end

  def resource_id_for_instance_id(id)
    # TODO(lsmola) we really need to get rid of the building our own emf_ref, it makes crosslinking impossible, parsing
    # the id string like this is suboptimal
    return nil unless id
    _, _, guid, _, resource_group, _, type, sub_type, name = id.split("/")
    File.join(guid, resource_group.downcase, type.downcase, sub_type.downcase, name)
  end
end
