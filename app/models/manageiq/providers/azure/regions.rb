module ManageIQ
  module Providers::Azure
    module Regions
      # The supported regions for the Azure provider. This is used by the UI
      # to display which regions are available when adding a new Azure provider.

      REGIONS = YAML.load_file(ManageIQ::Providers::Azure::Engine.root.join("db/fixtures/azure_regions.yml")).each_value(&:freeze).freeze

      # Returns an array of hashes corresponding to the REGIONS hash, excluding
      # disabled regions.
      #
      def self.regions
        additional_regions = Hash(Settings.ems.ems_azure&.additional_regions).stringify_keys
        disabled_regions   = Array(Settings.ems.ems_azure&.disabled_regions)

        REGIONS.merge(additional_regions).except(*disabled_regions)
      end

      # Returns an array of hashes corresponding to the REGIONS hash. Unlike
      # the +regions+ method, this only includes the values hash i.e. :name
      # and :description.
      #
      def self.all
        regions.values
      end

      # Return a simple array of region names. These correspond to the keys
      # in the REGIONS hash.
      #
      def self.names
        regions.keys
      end

      # Returns a hash containing :name and :description for region +name+.
      #
      # Example:
      #
      #   instance.find_by_name('eastus') # => {:name => 'eastus', :description => 'East US'}
      #
      def self.find_by_name(name)
        regions[name]
      end
    end
  end
end
