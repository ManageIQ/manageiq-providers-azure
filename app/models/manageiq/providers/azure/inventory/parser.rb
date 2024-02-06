class ManageIQ::Providers::Azure::Inventory::Parser < ManageIQ::Providers::Inventory::Parser
  include Vmdb::Logging

  TYPE_DEPLOYMENT = "microsoft.resources/deployments".freeze
end
