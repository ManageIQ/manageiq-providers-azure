module ManageIQ
  module Providers
    module Azure
      class Engine < ::Rails::Engine
        isolate_namespace ManageIQ::Providers::Azure

        config.autoload_paths << root.join('app', 'services')
        config.autoload_paths << root.join('lib')

        def self.vmdb_plugin?
          true
        end

        def self.plugin_name
          _('Azure Provider')
        end

        def self.init_loggers
          $azure_log ||= Vmdb::Loggers.create_logger("azure.log", Vmdb::Loggers::ProviderSdkLogger)
        end

        def self.apply_logger_config(config)
          Vmdb::Loggers.apply_config_value(config, $azure_log, :level_azure)
        end
      end
    end
  end
end
