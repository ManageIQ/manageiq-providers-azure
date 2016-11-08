module ManageIQ
  module Providers
    module Azure
      class Engine < ::Rails::Engine
        isolate_namespace ManageIQ::Providers::Azure
      end
    end
  end
end
