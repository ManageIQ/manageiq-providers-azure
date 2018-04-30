class ManageIQ::Providers::Azure::CloudManager::EventTargetParser
  attr_reader :ems_event

  # @param ems_event [EmsEvent] EmsEvent object
  def initialize(ems_event)
    @ems_event = ems_event
  end

  # Parses all targets that are present in the EmsEvent given in the initializer
  #
  # @return [Array] Array of ManagerRefresh::Target objects
  def parse
    parse_ems_event_targets(ems_event)
  end

  private

  # Parses list of ManagerRefresh::Target out of the given EmsEvent
  #
  # @param event [EmsEvent] EmsEvent object
  # @return [Array] Array of ManagerRefresh::Target objects
  def parse_ems_event_targets(event)
    target_collection = ManagerRefresh::TargetCollection.new(:manager => event.ext_management_system, :event => event)

    parse_event_target(target_collection, event.full_data)

    target_collection.targets
  end

  def parse_event_target(target_collection, event_data)
    resource_id   = event_data.try(:[], "resourceId")
    resource_type = event_data.try(:[], "resourceType").try(:[], "value")
    association   = case resource_type
                    when "Microsoft.Network/networkSecurityGroups", "Microsoft.Network/networkSecurityGroups/securityRules"
                      :security_groups
                    when "Microsoft.Network/networkInterfaces"
                      :network_ports
                    when "Microsoft.Compute/virtualMachines", "Microsoft.Authorization/locks"
                      :vms
                    when "Microsoft.Network/loadBalancers"
                      :load_balancers
                    when /Microsoft\.Network\/publicI[Pp]Addresses/
                      :floating_ips
                    when /Microsoft\.Network\/virtual[Nn]etworks/
                      :cloud_networks
                    when "Microsoft.Resources/deployments"
                      :orchestration_stacks
                    when "Microsoft.Compute/images"
                      :miq_templates
                    when /Microsoft\.Resources\/subscriptions\/resource[Gg]roups/
                      :resource_groups
                    when "Microsoft.Compute/availabilitySets"
                      :__unused
                    when "Microsoft.Compute/disks"
                      :__unused
                    when "Microsoft.Compute/snapshots"
                      :__unused
                    when "Microsoft.Storage/storageAccounts"
                      :__unused
                    end

    add_target(target_collection, association, resource_id) if association && resource_id
  end

  def transform_resource_id(association, resource_id)
    case association
    when :network_ports, :load_balancers, :resource_groups, :__unused
      fix_down_cased_resource_groups(resource_id)
    when :orchestration_stacks
      resource_id_for_stack_id(resource_id)
    when :vms
      resource_id_for_instance_id(resource_id)
    when :miq_templates
      resource_id.try(:downcase)
    when :floating_ips
      resource_id_for_floating_ips(resource_id)
    when :cloud_networks
      resource_id_for_cloud_networks(resource_id)
    when :security_groups
      resource_id_for_security_groups(resource_id)
    else
      resource_id
    end
  end

  def add_target(target_collection, association, ref)
    ref = transform_resource_id(association, ref)

    target_collection.add_target(:association => association, :manager_ref => {:ems_ref => ref}) if ref.present?
  end

  def fix_down_cased_resource_groups(id)
    return nil unless id

    array = id.split("/")
    array[3] = "resourceGroups" # fixing resource group naming that was down-cased in Azure for some reason
    standard_uid(array)
  end

  def resource_id_for_stack_id(id)
    # Transforming:
    # /subscriptions/SUBSCRIPTION_ID/resourcegroups/miq-azure-test1/deployments/Microsoft.LoadBalancer-20180305183523
    # to:
    # /subscriptions/SUBSCRIPTION_ID/resourceGroups/miq-azure-test1/providers/Microsoft.Resources/deployments/Microsoft.LoadBalancer-20180305183523
    # For some reason, the "providers/Microsoft.Resources" is missing in the middle and the resourcegroups is downcased
    return nil unless id
    array = id.split("/")
    array[3] = "resourceGroups" # fixing resource group naming that was down-cased in Azure for some reason

    standard_uid(array[0..4] + ["providers", "Microsoft.Resources"] + array[5..-1])
  end

  def resource_id_for_instance_id(id)
    return nil unless id
    _, _, guid, _, resource_group, _, type, sub_type, name = id.split("/")
    File.join(guid, resource_group.downcase, type.downcase, sub_type.downcase, name)
  end

  def resource_id_for_cloud_networks(id)
    id.gsub!("virtualnetworks", "virtualNetworks")
    id = id.split("/subnets/").first
    fix_down_cased_resource_groups(id)
  end

  def resource_id_for_floating_ips(id)
    id.gsub!("publicIpAddresses", "publicIPAddresses")
    fix_down_cased_resource_groups(id)
  end

  def resource_id_for_security_groups(id)
    id = id.split("/securityRules/").first
    fix_down_cased_resource_groups(id)
  end

  def standard_uid(*keys)
    keys.join("/")
  end
end
