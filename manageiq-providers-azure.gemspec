$:.push File.expand_path("../lib", __FILE__)

require "manageiq/providers/azure/version"

Gem::Specification.new do |s|
  s.name        = "manageiq-providers-azure"
  s.version     = ManageIQ::Providers::Azure::VERSION
  s.authors     = ["ManageIQ Developers"]
  s.homepage    = "https://github.com/ManageIQ/manageiq-providers-azure"
  s.summary     = "Azure Provider for ManageIQ"
  s.description = "Azure Provider for ManageIQ"
  s.licenses    = ["Apache-2.0"]

  s.files = Dir["{app,config,lib}/**/*"]

  s.add_dependency "azure-armrest", "~>0.9.1"

  s.add_development_dependency "codeclimate-test-reporter", "~> 1.0.0"
  s.add_development_dependency "simplecov"
end
