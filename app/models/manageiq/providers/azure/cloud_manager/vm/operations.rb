module ManageIQ::Providers::Azure::CloudManager::Vm::Operations
  extend ActiveSupport::Concern
  include Power

  included do
    supports :terminate do
      unsupported_reason_add(:terminate, unsupported_reason(:control)) unless supports?(:control)
    end
  end

  def raw_destroy
    unless ext_management_system
      raise _("VM has no %{table}, unable to destroy VM") % {:table => ui_lookup(:table => "ext_management_systems")}
    end
    provider_service.delete_associated_resources(name, resource_group.name, :data_disks => true)
    update!(:raw_power_state => "Deleting")
  end
end
