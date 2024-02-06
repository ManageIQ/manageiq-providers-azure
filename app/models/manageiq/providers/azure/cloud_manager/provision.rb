class ManageIQ::Providers::Azure::CloudManager::Provision < ManageIQ::Providers::CloudManager::Provision
  include Cloning
  include Configuration
  include OptionsHelper
  include StateMachine
end
