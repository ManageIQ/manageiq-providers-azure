module ManageIQ::Providers::Azure::CloudManager::VmOrTemplateShared
  extend ActiveSupport::Concern
  include_concern 'Scanning'
  SSA_SNAPSHOT_SUFFIX = "__EVM__SSA__SNAPSHOT".freeze

  def provider_service(connection = nil)
    @connection ||= connection || ext_management_system.connect
    @provider_service ||= ::Azure::Armrest::VirtualMachineService.new(@connection)
  end

  def storage_acct_service(connection = nil)
    @connection ||= connection || ext_management_system.connect
    @storage_acct_service ||= ::Azure::Armrest::StorageAccountService.new(@connection)
  end

  def blob_info
    @blob_info ||= storage_acct_service.parse_uri(blob_uri)
  end

  def container
    @container ||= blob_info[:container]
  end

  def blob
    @blob ||= blob_info[:blob]
  end

  def storage_acct
    @storage_acct ||= storage_acct_service.accounts_by_name[blob_info[:account_name]]
  end

  def key
    @key ||= storage_acct_service.list_account_keys(storage_acct.name, storage_acct.resource_group).fetch('key1')
  end

  def vm_object
    @vm_object ||= provider_service.get(name, resource_group.name)
  end

  def os_disk
    @os_disk ||= vm_object.properties.storage_profile.os_disk
  end

  def managed_disk?
    vm_object.managed_disk?
  end

  def snap_name
    @snap_name ||= "#{os_disk.name}#{SSA_SNAPSHOT_SUFFIX}"
  end

  def blob_uri
    @blob_uri ||= os_disk.vhd.uri
  end
end
