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
  config.define_cassette_placeholder(Rails.application.secrets.azure_defaults[:client_id]) do
    Rails.application.secrets.azure[:client_id]
  end
  config.define_cassette_placeholder(Rails.application.secrets.azure_defaults[:client_secret]) do
    Rails.application.secrets.azure[:client_secret]
  end
  config.define_cassette_placeholder(Rails.application.secrets.azure_defaults[:tenant_id]) do
    Rails.application.secrets.azure[:tenant_id]
  end
  config.define_cassette_placeholder(Rails.application.secrets.azure_defaults[:subscription_id]) do
    Rails.application.secrets.azure[:subscription_id]
  end
end
