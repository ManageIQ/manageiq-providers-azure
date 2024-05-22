module ManageIQ::Providers::Azure::CloudManager::Vm::Operations::Power
  extend ActiveSupport::Concern

  included do
    supports :reboot_guest do
      if current_state == "on"
        unsupported_reason(:control)
      else
        _("The VM is not powered on")
      end
    end

    supports_not :pause, :reason => "Pause Operation is not available for Azure Instances"
    supports_not :reset, :reason => "Hard reboot not supported on Azure"
  end

  def raw_suspend
    provider_service.stop(name, resource_group.name)
    update!(:raw_power_state => "VM stopping")
  end

  def raw_start
    provider_service.start(name, resource_group.name)
    update!(:raw_power_state => "VM starting")
  end

  def raw_stop
    provider_service.deallocate(name, resource_group.name)
    update!(:raw_power_state => "VM deallocating")
  end

  def raw_restart
    provider_service.restart(name, resource_group.name)
    update!(:raw_power_state => "VM starting")
  end

  def reboot_guest
    provider_service.restart(name, resource_group.name)
    update!(:raw_power_state => "VM starting")
  end
end
