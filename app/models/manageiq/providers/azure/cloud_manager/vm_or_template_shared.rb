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

  def image_service(connection = nil)
    @connection ||= connection || ext_management_system.connect
    @image_service ||= ::Azure::Armrest::Storage::ImageService.new(@connection)
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
    @vm_object ||= provider_service.get(name, resource_group)
  end

  def image_object
    @image_object ||= image_service.get(name, managed_resource_group)
  end

  def os_disk
    @os_disk ||= if template
                   image_object.properties.storage_profile.os_disk
                 else
                   vm_object.properties.storage_profile.os_disk
                 end
  end

  delegate :managed_disk?, to: :vm_object

  def managed_image?
    return false unless ems_ref =~ /^\/subscriptions\//i
    os_disk.try(:managed_disk) ? true : false
  end

  def managed_resource_group
    return nil unless ems_ref =~ /^\/subscriptions\//i
    ref_parts = ems_ref.split('/')
    if ref_parts[3] =~ /resourceGroups/i
      return ref_parts[4]
    end
    nil
  end

  def managed_image_disk_name
    return nil unless managed_image?
    @managed_image_disk_name ||= File.basename(os_disk.managed_disk.id)
  end

  def ssa_snap_name
    @ssa_snap_name ||= "#{os_disk.name}#{SSA_SNAPSHOT_SUFFIX}"
  end

  def blob_uri
    if template
      if ems_ref =~ /^https:/
        @blob_uri ||= ems_ref
      elsif os_disk.try(:blob_uri)
        @blob_uri ||= os_disk.blob_uri
      end
    else
      @blob_uri ||= os_disk.vhd.uri
    end
    @blob_uri
  end
end
