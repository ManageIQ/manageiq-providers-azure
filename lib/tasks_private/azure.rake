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

      regions += additional_regions

      regions_by_name = regions.sort_by { |r| r[:name] }.index_by { |r| r[:name] }
      File.write("config/regions.yml", regions_by_name.to_yaml)
    end

    private

    # These are regions that are not returned by list-locations using a subscription that we have access to
    def additional_regions
      [
        {:name => "germanycentral",   :description => "Germany Central"},
        {:name => "germanynortheast", :description => "Germany Northeast"},
        {:name => "usgovarizona",     :description => "US Gov Arizona"},
        {:name => "usgoviowa",        :description => "US Gov Iowa"},
        {:name => "usgovtexas",       :description => "US Gov Texas"},
        {:name => "usgovvirginia",    :description => "US Gov Virginia"}
      ]
    end
  end
end
