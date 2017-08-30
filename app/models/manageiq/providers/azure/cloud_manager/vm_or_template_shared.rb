module ManageIQ::Providers::Azure::CloudManager::VmOrTemplateShared
  extend ActiveSupport::Concern
  include_concern 'Scanning'

  def provider_service(connection = nil)
    connection ||= ext_management_system.connect
    ::Azure::Armrest::VirtualMachineService.new(connection)
  end
end
