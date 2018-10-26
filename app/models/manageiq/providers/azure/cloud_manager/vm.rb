class ManageIQ::Providers::Azure::CloudManager::Vm < ManageIQ::Providers::CloudManager::Vm
  include_concern 'Operations'
  include_concern 'ManageIQ::Providers::Azure::CloudManager::VmOrTemplateShared'

  # Only select the columns we actually use for the Azure provider.
  default_scope do
    select([
      :availability_zone_id,
      :cloud,
      :created_on,
      :description,
      :ems_id,
      :ems_ref,
      :flavor_id,
      :guid,
      :location,
      :name,
      :orchestration_stack_id,
      :power_state,
      :publicly_available,
      :raw_power_state,
      :resource_group_id,
      :state_changed_on,
      :tenant_id,
      :type,
      :uid_ems,
      :vendor
    ])
  end

  #
  # Relationship methods
  #

  def disconnect_inv
    super

    # Mark all instances no longer found as unknown
    self.raw_power_state = "unknown"
    save
  end

  def disconnected
    false
  end

  def disconnected?
    false
  end

  def memory_mb_available?
    true
  end

  def self.calculate_power_state(raw_power_state)
    case raw_power_state.downcase
    when /running/, /starting/
      "on"
    when /stopped/, /stopping/
      "suspended"
    when /dealloc/
      "off"
    else
      "unknown"
    end
  end

  def self.display_name(number = 1)
    n_('Instance (Microsoft Azure)', 'Instances (Microsoft Azure)', number)
  end
end
