class ManageIQ::Providers::Azure::Inventory::Parser < ManageIQ::Providers::Inventory::Parser
  require_nested :ContainerManager
  require_nested :CloudManager
  require_nested :NetworkManager

  include Vmdb::Logging

  TYPE_DEPLOYMENT = "microsoft.resources/deployments".freeze
end
