module ManageIQ
  module Providers::Azure
    module Regions
      # The supported regions for the Azure provider. This is used by the UI
      # to display which regions are available when adding a new Azure provider.

      REGIONS = {
        "australiaeast"      => {
          :name        => "australiaeast",
          :description => _("Australia East"),
        },
        "australiacentral"   => {
          :name        => "australiacentral",
          :description => _("Australia Central"),
        },
        "australiacentral2"  => {
          :name        => "australiacentral2",
          :description => _("Australia Central 2"),
        },
        "australiasoutheast" => {
          :name        => "australiasoutheast",
          :description => _("Australia Southeast"),
        },
        "brazilsouth"        => {
          :name        => "brazilsouth",
          :description => _("Brazil South"),
        },
        "canadacentral"      => {
          :name        => "canadacentral",
          :description => _("Canada Central"),
        },
        "canadaeast"         => {
          :name        => "canadaeast",
          :description => _("Canada East"),
        },
        "centralindia"       => {
          :name        => "centralindia",
          :description => _("Central India"),
        },
        "centralus"          => {
          :name        => "centralus",
          :description => _("Central US"),
        },
        "eastasia"           => {
          :name        => "eastasia",
          :description => _("East Asia"),
        },
        "eastus"             => {
          :name        => "eastus",
          :description => _("East US"),
        },
        "eastus2"            => {
          :name        => "eastus2",
          :description => _("East US 2"),
        },
        "francecentral"      => {
          :name        => "francecentral",
          :description => _("France Central"),
        },
        "francesouth"        => {
          :name        => "francesouth",
          :description => _("France South"),
        },
        "germanycentral"     => {
          :name        => "germanycentral",
          :description => _("Germany Central"),
        },
        "germanynorth"       => {
          :name        => "germanynorth",
          :description => _("Germany North"),
        },
        "germanynortheast"   => {
          :name        => "germanynortheast",
          :description => _("Germany Northeast"),
        },
        "germanywestcentral" => {
          :name        => "germanywestcentral",
          :description => _("Germany West Central"),
        },
        "japaneast"          => {
          :name        => "japaneast",
          :description => _("Japan East"),
        },
        "japanwest"          => {
          :name        => "japanwest",
          :description => _("Japan West"),
        },
        "koreacentral"       => {
          :name        => "koreacentral",
          :description => _("Korea Central"),
        },
        "koreasouth"         => {
          :name        => "koreasouth",
          :description => _("Korea South"),
        },
        "northcentralus"     => {
          :name        => "northcentralus",
          :description => _("North Central US"),
        },
        "northeurope"        => {
          :name        => "northeurope",
          :description => _("North Europe"),
        },
        "southcentralus"     => {
          :name        => "southcentralus",
          :description => _("South Central US"),
        },
        "southeastasia"      => {
          :name        => "southeastasia",
          :description => _("Southeast Asia"),
        },
        "southindia"         => {
          :name        => "southindia",
          :description => _("South India"),
        },
        "uksouth"            => {
          :name        => "uksouth",
          :description => _("UK South"),
        },
        "ukwest"             => {
          :name        => "ukwest",
          :description => _("UK West"),
        },
        "usgovarizona"       => {
          :name        => "usgovarizona",
          :description => _("US Gov Arizona"),
        },
        "usgoviowa"          => {
          :name        => "usgoviowa",
          :description => _("US Gov Iowa"),
        },
        "usgovtexas"         => {
          :name        => "usgovtexas",
          :description => _("US Gov Texas"),
        },
        "usgovvirginia"      => {
          :name        => "usgovvirginia",
          :description => _("US Gov Virginia"),
        },
        "westeurope"         => {
          :name        => "westeurope",
          :description => _("West Europe"),
        },
        "westindia"          => {
          :name        => "westindia",
          :description => _("West India"),
        },
        "westcentralus"      => {
          :name        => "westcentralus",
          :description => _("West Central US"),
        },
        "westus"             => {
          :name        => "westus",
          :description => _("West US"),
        },
        "westus2"            => {
          :name        => "westus2",
          :description => _("West US 2"),
        },
      }.freeze

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
