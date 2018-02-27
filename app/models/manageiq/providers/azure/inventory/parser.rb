class ManageIQ::Providers::Azure::Inventory::Parser < ManagerRefresh::Inventory::Parser
  require_nested :CloudManager
  require_nested :NetworkManager

  include Vmdb::Logging

  TYPE_DEPLOYMENT = "microsoft.resources/deployments".freeze

  # Compose an id string combining some existing keys
  def resource_uid(*keys)
    keys.join('\\')
  end
end
