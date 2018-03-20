namespace :manageiq do
  namespace :providers do
    namespace :azure do
      namespace :spec do
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
            yml_file  = Dir["#{cass_dir}/**/refresher.yml"].first
            spec_file = Dir["#{spec_dir}/**/refresher_spec.rb"].first
            FileUtils.rm(yml_file, :verbose => true) if yml_file
            sh "bundle exec rspec #{spec_file}"
          end
        end
      end
    end
  end
end
