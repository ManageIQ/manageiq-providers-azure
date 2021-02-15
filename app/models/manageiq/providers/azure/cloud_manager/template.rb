class ManageIQ::Providers::Azure::CloudManager::Template < ::ManageIQ::Providers::CloudManager::Template
  include_concern 'ManageIQ::Providers::Azure::CloudManager::VmOrTemplateShared'

  supports :provisioning do
    if ext_management_system
      unsupported_reason_add(:provisioning, ext_management_system.unsupported_reason(:provisioning)) unless ext_management_system.supports?(:provisioning)
    else
      unsupported_reason_add(:provisioning, _('not connected to ems'))
    end
  end

  def provider_object(connection = nil)
    connection ||= ext_management_system.connect
    connection.images[ems_ref]
  end

  def self.display_name(number = 1)
    n_('Image (Microsoft Azure)', 'Images (Microsoft Azure)', number)
  end
end
