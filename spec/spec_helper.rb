if ENV['CI']
  require 'simplecov'
  SimpleCov.start
end

VCR.configure do |config|
  config.ignore_hosts 'codeclimate.com' if ENV['CI']
  config.cassette_library_dir = File.join(ManageIQ::Providers::Azure::Engine.root, 'spec/vcr_cassettes')
  config.default_cassette_options = {
    :match_requests_on => [
      :method,
      VCR.request_matchers.uri_without_param('api-version')
    ]
  }
  # config.debug_logger = File.open('vcr.debug', 'w')
end

Dir[Rails.root.join("spec/shared/**/*.rb")].each { |f| require f }
Dir[ManageIQ::Providers::Azure::Engine.root.join("spec/support/**/*.rb")].each { |f| require f }
