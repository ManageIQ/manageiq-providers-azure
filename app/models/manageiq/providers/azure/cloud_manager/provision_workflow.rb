class ManageIQ::Providers::Azure::CloudManager::ProvisionWorkflow < ManageIQ::Providers::CloudManager::ProvisionWorkflow
  def allowed_instance_types(_options = {})
    source = load_ar_obj(get_source_vm)
    ems    = source.try(:ext_management_system)
    return {} if ems.nil?
    flavors = ems.flavors
    flavors.each_with_object({}) { |f, hash| hash[f.id] = display_name_for_name_description(f) }
  end

  def allowed_resource_groups(_options = {})
    source = load_ar_obj(get_source_vm)
    ems    = source.try(:ext_management_system)
    return {} if ems.nil?
    resource_groups = ems.resource_groups
    resource_groups.each_with_object({}) { |rg, hash| hash[rg.id] = rg.name }
  end

  def allowed_cloud_subnets(_options = {})
    src = resources_for_ui
    if (cn = CloudNetwork.find_by(:id => src[:cloud_network_id]))
      cn.cloud_subnets.each_with_object({}) do |cs, hash|
        hash[cs.id] = "#{cs.name} (#{cs.cidr})"
      end
    else
      {}
    end
  end

  def allowed_floating_ip_addresses(options = {})
    num_vms_selected = dialog_field_visibility_service.number_of_vms_visibility_service.number_of_vms

    if num_vms_selected > 1
      {-1 => 'New'}
    else
      super(options).merge(-1 => 'New')
    end
  end

  def supports_sysprep?
    true
  end

  def self.provider_model
    ManageIQ::Providers::Azure::CloudManager
  end

  private

  def dialog_name_from_automate(message = 'get_dialog_name')
    super(message, {'platform' => 'azure'})
  end

  def dialog_field_visibility_service
    @dialog_field_visibility_service ||= ManageIQ::Providers::Azure::DialogFieldVisibilityService.new
  end
end
