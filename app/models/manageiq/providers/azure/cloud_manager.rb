class ManageIQ::Providers::Azure::CloudManager < ManageIQ::Providers::CloudManager
  require_nested :AvailabilityZone
  require_nested :EventCatcher
  require_nested :EventParser
  require_nested :Flavor
  require_nested :MetricsCapture
  require_nested :MetricsCollectorWorker
  require_nested :RefreshParser
  require_nested :RefreshWorker
  require_nested :Refresher
  require_nested :Vm
  require_nested :Template
  require_nested :Provision
  require_nested :ProvisionWorkflow
  require_nested :OrchestrationStack
  require_nested :OrchestrationTemplate
  require_nested :OrchestrationServiceOptionConverter

  include ManageIQ::Providers::Azure::ManagerMixin

  alias_attribute :azure_tenant_id, :uid_ems

  has_many :resource_groups, :foreign_key => :ems_id, :dependent => :destroy

  supports :discovery
  supports :provisioning
  supports :regions

  supports :timeline do
    unless insights?
      unsupported_reason_add(:timeline, _('Timeline not supported for this region'))
    end
  end

  before_create :ensure_managers
  before_update :ensure_managers_zone_and_provider_region

  # If the Microsoft.Insights Azure provider is not registered, then neither
  # events nor metrics are supported for that EMS.
  #
  def insights?
    require 'azure-armrest'
    with_provider_connection do |conf|
      rps = ::Azure::Armrest::ResourceProviderService.new(conf)
      rps.get('Microsoft.Insights').registration_state.casecmp('registered').zero?
    end
  end

  def ensure_network_manager
    build_network_manager(:type => 'ManageIQ::Providers::Azure::NetworkManager') unless network_manager
  end

  def self.ems_type
    @ems_type ||= "azure".freeze
  end

  def self.description
    @description ||= "Azure".freeze
  end

  def self.default_blacklisted_event_names
    %w(
      storageAccounts_listKeys_BeginRequest
      storageAccounts_listKeys_EndRequest
    )
  end

  def blacklisted_provider_types
    %r{Microsoft.Classic}
  end

  def self.hostname_required?
    false
  end

  def description
    ManageIQ::Providers::Azure::Regions.find_by_name(provider_region)[:description]
  end

  # Operations

  def vm_start(vm, _options = {})
    vm.start
  rescue => err
    _log.error "vm=[#{vm.name}], error: #{err}"
  end

  def vm_stop(vm, _options = {})
    vm.stop
  rescue => err
    _log.error "vm=[#{vm.name}], error: #{err}"
  end

  def vm_suspend(vm, _options = {})
    vm.suspend
  rescue => err
    _log.error "vm=[#{vm.name}], error: #{err}"
  end

  def vm_destroy(vm, _options = {})
    vm.vm_destroy
  rescue => err
    _log.error "vm=[#{vm.name}], error: #{err}"
  end

  def vm_restart(vm, _options = {})
    # TODO switch to vm.restart
    vm.raw_restart
  rescue => err
    _log.error "vm=[#{vm.name}], error: #{err}"
  end

  def vm_reboot_guest(vm, _options = {})
    vm.reboot_guest
  rescue => err
    _log.error "vm=[#{vm.name}], error: #{err}"
  end

  def vm_create_evm_snapshot(vm, options = {})
    @connection = connect(options)
    vm.provider_service(@connection)
    if vm.managed_disk?
      vm_create_evm_managed_snapshot(vm)
    else
      vm_create_evm_blob_snapshot(vm)
    end
  end

  def vm_create_evm_managed_snapshot(vm)
    snap_svc     = snapshot_service(@connection)
    snap_options = { :location   => vm.location,
                     :properties => {
                       :creationData => {
                         :createOption     => "Copy",
                         :sourceResourceId => vm.os_disk.managed_disk.id
                       }
                     } }
    _log.debug("vm=[#{vm.name}] creating SSA snapshot #{vm.snap_name}")
    begin
      snap_name      = vm.snap_name
      resource_group = vm.resource_group.name
      snap_svc.get(snap_name, resource_group)
    rescue ::Azure::Armrest::NotFoundException, ::Azure::Armrest::ResourceNotFoundException => err
      begin
        snap_svc.create(snap_name, resource_group, snap_options)
        return snap_name
      rescue => err
        _log.error("vm=[#{vm.name}], error: #{err}")
        _log.debug { err.backtrace.join("\n") }
        raise "Error #{err} creating SSA Snapshot #{snap_name}"
      end
    end
    _log.error("SSA Snapshot #{snap_name} already exists.")
    raise "Snapshot #{snap_name} already exists. Another SSA request for this VM is in progress or a previous one failed to clean up properly."
  end

  def vm_create_evm_blob_snapshot(vm)
    _log.debug("vm=[#{vm.name}] creating SSA snapshot for #{vm.blob_uri}")
    begin
      snapshot_info = vm.storage_acct.create_blob_snapshot(vm.container, vm.blob, vm.key)
      return snapshot_info[:x_ms_snapshot]
    rescue => err
      _log.error("vm=[#{vm.name}], error:#{err}")
      _log.debug { err.backtrace.join("\n") }
      raise "Error #{err} creating SSA Snapshot for #{vm.name}"
    end
  end

  def vm_delete_evm_snapshot(vm, options = {})
    @connection = connect(options)
    if vm.managed_disk?
      vm_delete_managed_snapshot(vm, options)
    else
      vm_delete_blob_snapshot(vm, options)
    end
  end

  def vm_delete_managed_snapshot(vm, options = {})
    snap_svc  = snapshot_service(@connection)
    _log.debug("vm=[#{vm.name}] deleting SSA snapshot #{vm.snap_name}")
    snap_svc.delete(vm.snap_name, vm.resource_group.name)
  rescue => err
    _log.error("vm=[#{vm.name}], error: #{err} deleting SSA snapshot #{vm.snap_name}")
    _log.debug { err.backtrace.join("\n") }
  end

  def vm_delete_blob_snapshot(vm, options = {})
    unless options[:snMor]
      _log.error("Unable to clean up SSA snapshot: Missing Snapshot Date")
      return
    end
    _log.debug("vm=[#{vm.name}] deleting SSA snapshot for #{vm.blob_uri} with date #{options[:snMor]}")
    begin
      snap_opts = { :date => options[:snMor] }
      vm.storage_acct.delete_blob(vm.container, vm.blob, vm.key, snap_opts)
    rescue => err
      _log.error("vm=[#{vm.name}], error:#{err} deleting SSA snapshot with date #{options[:snMor]}")
      _log.debug { err.backtrace.join("\n") }
    end
  end

  def snapshot_service(connection = nil)
    _log.debug("Enter")
    connection ||= connect
    ::Azure::Armrest::Storage::SnapshotService.new(connection)
  end
end
