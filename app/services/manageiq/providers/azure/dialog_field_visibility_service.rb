class ManageIQ::Providers::Azure::DialogFieldVisibilityService < ::DialogFieldVisibilityService
  attr_reader :number_of_vms_visibility_service

  def initialize(
    auto_placement_visibility_service = AutoPlacementVisibilityService.new,
    number_of_vms_visibility_service = ManageIQ::Providers::Azure::NumberOfVmsVisibilityService.new,
    service_template_fields_visibility_service = ServiceTemplateFieldsVisibilityService.new,
    network_visibility_service = NetworkVisibilityService.new,
    sysprep_auto_logon_visibility_service = SysprepAutoLogonVisibilityService.new,
    retirement_visibility_service = RetirementVisibilityService.new,
    customize_fields_visibility_service = CustomizeFieldsVisibilityService.new,
    sysprep_custom_spec_visibility_service = SysprepCustomSpecVisibilityService.new,
    request_type_visibility_service = RequestTypeVisibilityService.new,
    pxe_iso_visibility_service = PxeIsoVisibilityService.new,
    linked_clone_visibility_service = LinkedCloneVisibilityService.new
  )
    super
  end
end
