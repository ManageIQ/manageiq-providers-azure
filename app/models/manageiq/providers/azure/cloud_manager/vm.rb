class ManageIQ::Providers::Azure::CloudManager::Vm < ManageIQ::Providers::CloudManager::Vm
  include_concern 'Operations'
  include_concern 'ManageIQ::Providers::Azure::CloudManager::VmOrTemplateShared'

  UNSUPPORTED_COLUMNS = %w[
    busy
    config_xml
    cpu_affinity
    cpu_hot_add_enabled
    cpu_hot_remove_enabled
    cpu_limit
    cpu_reserve
    cpu_reserve_expand
    cpu_shares
    cpu_shares_level
    deprecated
    fault_tolerance
    format
    linked_clone
    memory_hot_add_enabled
    memory_hot_add_increment
    memory_hot_add_limit
    memory_limit
    memory_reserve
    memory_reserve_expand
    memory_shares
    memory_shares_level
    registered
    tools_status
  ].freeze

  # Exclude columns that are not used by Azure.
  default_scope do
    select(VmOrTemplate.column_names - UNSUPPORTED_COLUMNS)
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
