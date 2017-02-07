require 'bundler/setup'
require 'bundler/gem_tasks'

begin
  require 'rspec/core/rake_task'

  APP_RAKEFILE = File.expand_path("../spec/manageiq/Rakefile", __FILE__)
  load 'rails/tasks/engine.rake'
rescue LoadError
end

namespace :spec do
  desc "Setup environment for specs"
  task :setup => 'app:test:providers:azure:setup'
end

desc "Run all azure specs"
task :spec => 'app:test:providers:azure'

task :default => :spec
