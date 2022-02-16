namespace :azure do
  namespace :regions do
    desc "List all regions"
    task :list => :environment do
      puts physical_regions.map { |r| "#{r["name"]} - #{r["displayName"]}" }.join("\n")
    end

    desc "Update list of regions"
    task :update => :environment do
      regions = physical_regions.map do |region|
        {
          :name        => region["name"],
          :description => region["displayName"]
        }
      end

      regions += additional_regions

      regions_by_name = regions.sort_by { |r| r[:name] }.index_by { |r| r[:name] }
      File.write("db/fixtures/azure_regions.yml", regions_by_name.to_yaml)
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

    def physical_regions
      # Only physical regions (not logical regions) can be used
      stdout, status = Open3.capture2("az account list-locations --query \"[?contains(metadata.regionType, 'Physical')]\"")
      raise status unless status.success?

      JSON.parse(stdout)
    end
  end
end
