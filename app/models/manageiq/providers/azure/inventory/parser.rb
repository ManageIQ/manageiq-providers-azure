class ManageIQ::Providers::Azure::Inventory::Parser < ManagerRefresh::Inventory::Parser
  require_nested :CloudManager
  require_nested :NetworkManager

  include Vmdb::Logging

  TYPE_DEPLOYMENT = "microsoft.resources/deployments".freeze
end
