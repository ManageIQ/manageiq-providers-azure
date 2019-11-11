module ManageIQ::Providers::Azure::CloudManager::VmOrTemplateShared::Scanning
  extend ActiveSupport::Concern

  included do
    supports :smartstate_analysis do
      feature_supported, reason = check_feature_support('smartstate_analysis')
      unless feature_supported
        unsupported_reason_add(:smartstate_analysis, reason)
      end
    end
  end

  #
  # Adjustment Multiplier is 4 (i.e. 4 times the specified timeout)
  #
  def self.scan_timeout_adjustment_multiplier
    4
  end

  def perform_metadata_scan(ost)
    require 'MiqVm/miq_azure_vm'

    vm_args = { :name => name }
    _log.debug("name: #{name} (template = #{template})")
    if template
      if managed_image?
        vm_args[:resource_group] = managed_resource_group
        vm_args[:managed_image]  = managed_image_disk_name
      elsif blob_uri
        vm_args[:image_uri] = blob_uri
      else
        vm_args[:image_uri] = uid_ems
      end
    else
      vm_args[:resource_group] = resource_group.name
      vm_args[:snapshot] = ost.scanData["snapshot"]["name"]
    end

    ost.scanTime = Time.now.utc unless ost.scanTime
    armrest      = ext_management_system.connect

    begin
      miq_vm = MiqAzureVm.new(armrest, vm_args)
      scan_via_miq_vm(miq_vm, ost)
    ensure
      miq_vm&.unmount
    end
  end

  def perform_metadata_sync(ost)
    sync_stashed_metadata(ost)
  end

  def proxies4job(_job)
    {
      :proxies => [MiqServer.my_server],
      :message => 'Perform SmartState Analysis on this Instance'
    }
  end

  def has_active_proxy?
    true
  end

  def has_proxy?
    true
  end

  def requires_storage_for_scan?
    false
  end

  def require_snapshot_for_scan?
    true
  end
end
