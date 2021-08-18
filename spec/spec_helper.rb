if ENV['CI']
  require 'simplecov'
  SimpleCov.start
end

Dir[Rails.root.join("spec/shared/**/*.rb")].each { |f| require f }
Dir[File.join(__dir__, "support/**/*.rb")].each { |f| require f }

require "manageiq-providers-azure"

VCR.configure do |config|
  config.ignore_hosts 'codeclimate.com' if ENV['CI']
  config.cassette_library_dir = File.join(ManageIQ::Providers::Azure::Engine.root, 'spec/vcr_cassettes')
  config.default_cassette_options = {
    :match_requests_on => [
      :method,
      VCR.request_matchers.uri_without_param('api-version')
    ]
  }

  secrets = Rails.application.secrets
  secrets.azure.each do |key, val|
    config.define_cassette_placeholder(secrets.azure_defaults[key]) { val }
  end
  secrets.azure_aks.each do |key, val|
    config.define_cassette_placeholder(secrets.azure_aks_defaults[key]) { val }
  end
end
