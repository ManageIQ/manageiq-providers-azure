namespace :azure do
  namespace :regions do
    desc "List all regions"
    task :list => :environment do
      stdout, status = Open3.capture2('az account list-locations')
      raise status unless status.success?

      regions = JSON.parse(stdout)
      puts regions.map { |r| "#{r["name"]} - #{r["displayName"]}" }.join("\n")
    end

    desc "Update list of regions"
    task :update => :environment do
      stdout, status = Open3.capture2('az account list-locations')
      raise status unless status.success?

      regions = JSON.parse(stdout).map do |region|
        {
          :name        => region["name"],
          :description => region["displayName"]
        }
      end

      regions_by_name = regions.sort_by { |r| r[:name] }.index_by { |r| r[:name] }
      File.write("db/fixtures/azure_regions.yml", regions_by_name.to_yaml)
    end
  end
end
