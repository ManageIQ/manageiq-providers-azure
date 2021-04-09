class ManageIQ::Providers::Azure::Inventory < ManageIQ::Providers::Inventory
  require_nested :Collector
  require_nested :Parser
  require_nested :Persister

  # Default manager for building collector/parser/persister classes
  # when failed to get class name from refresh target automatically
  def self.default_manager_name
    "CloudManager"
  end

  def self.parser_classes_for(_ems, _target)
    [ManageIQ::Providers::Azure::Inventory::Parser::CloudManager, ManageIQ::Providers::Azure::Inventory::Parser::NetworkManager]
  end
end
