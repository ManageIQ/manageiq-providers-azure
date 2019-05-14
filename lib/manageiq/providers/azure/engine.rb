module ManageIQ
  module Providers
    module Azure
      class Engine < ::Rails::Engine
        isolate_namespace ManageIQ::Providers::Azure
        config.autoload_paths << root.join('app', 'services').to_s

        def self.vmdb_plugin?
          true
        end

        def self.plugin_name
          _('Azure Provider')
        end
      end
    end
  end
end
