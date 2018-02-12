module ManageIQ
  module Providers
    module Azure
      class Engine < ::Rails::Engine
        isolate_namespace ManageIQ::Providers::Azure
        config.autoload_paths << root.join('app', 'services').to_s
      end
    end
  end
end
