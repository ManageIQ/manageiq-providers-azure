module ManageIQ::Providers::Azure::CloudManager::VmOrTemplateShared
  extend ActiveSupport::Concern
  include_concern 'Scanning'

  def provider_service(connection = nil)
    connection ||= ext_management_system.connect
    ::Azure::Armrest::VirtualMachineService.new(connection)
  end

  # The resource group is stored as part of the uid_ems. This splits it out.
  def resource_group
    uid_ems.split('\\')[1]
  end
end
