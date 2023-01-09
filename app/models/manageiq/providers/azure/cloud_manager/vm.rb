class ManageIQ::Providers::Azure::CloudManager::Vm < ManageIQ::Providers::CloudManager::Vm
  include_concern 'Operations'
  include_concern 'ManageIQ::Providers::Azure::CloudManager::VmOrTemplateShared'

  supports :capture

  #
  # Relationship methods
  #

  def disconnect_inv
    super

    # Mark all instances no longer found as unknown
    self.raw_power_state = "unknown"
    save
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
