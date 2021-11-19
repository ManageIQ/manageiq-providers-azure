namespace :spec do
  desc "Setup environment specs"
  task :setup => ["app:test:vmdb:setup"]

  namespace :regenerate do
    base_dir = File.join(ManageIQ::Providers::Azure::Engine.config.root.to_s, 'spec')
    cass_dir = File.join(base_dir, 'vcr_cassettes/manageiq/providers/azure')
    spec_dir = File.join(base_dir, 'models/manageiq/providers/azure')

    desc "Regenerate all the cassettes"
    task :all do
      Dir["#{cass_dir}/**/*.yml"].each do |file|
        FileUtils.rm(file, :verbose => true)
      end
      sh "bundle exec rspec"
    end

    desc "Regenerate the refresher cassette"
    task :refresher do
      spec_file = Dir["#{spec_dir}/**/refresher_spec.rb"].first
      Dir["#{cass_dir}/**/refresher*.yml"].each do |file|
        FileUtils.rm(file, :verbose => true)
      end
      sh "bundle exec rspec #{spec_file}"
    end
  end
end

desc "Run all specs"
RSpec::Core::RakeTask.new(:spec => ['app:test:spec_deps', 'app:test:providers_common']) do |t|
  EvmTestHelper.init_rspec_task(t)
end
