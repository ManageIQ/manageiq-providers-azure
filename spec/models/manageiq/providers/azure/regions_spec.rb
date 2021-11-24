describe ManageIQ::Providers::Azure::Regions do

  context "region list" do
    let(:eastus) { {:name => "eastus", :description => "East US"} }
    let(:germanycentral) { {:name => "germanycentral", :description => "Germany Central"} }

    # You can get these by running Azure::Armrest::ArmrestService#list_locations
    def azure_regions
      %w(
        australiacentral australiacentral2 australiaeast australiasoutheast
        brazilsouth canadacentral canadaeast centralindia centralus eastasia
        eastus eastus2 francecentral francesouth
        germanycentral germanynorth germanynortheast germanywestcentral
        japaneast japanwest koreacentral koreasouth
        northcentralus northeurope southcentralus southeastasia
        southindia uksouth ukwest usgovarizona usgoviowa usgovtexas usgovvirginia
        westcentralus westeurope westindia westus westus2
      )
    end

    it "returns the expected array for the names method" do
      expect(described_class.names).to include(*azure_regions)
    end

    it "returns expected results for the all method" do
      expect(described_class.all).to include(eastus)
      expect(described_class.all).to include(germanycentral)
    end
  end

  context "disable regions via Settings" do
    it "contains gov_cloud without it being disabled" do
      stub_settings(:ems => {:ems_azure => {:disabled_regions => []}})
      expect(described_class.names).to include("usgoviowa")
    end

    it "contains gov_cloud without disabled_regions being set at all - for backwards compatibility" do
      stub_settings(:ems => {})
      expect(described_class.names).to include("usgoviowa")
    end

    it "does not contain some regions that are disabled" do
      stub_settings(:ems => {:ems_azure => {:disabled_regions => ['usgoviowa']}})
      expect(described_class.names).not_to include('usgoviowa')
    end
  end

  context "add regions via settings" do
    context "with no additional regions set" do
      let(:settings) do
        {:ems => {:ems_azure => {:additional_regions => nil}}}
      end

      it "returns standard regions" do
        stub_settings(settings)
        expect(described_class.names).to eql(described_class.send(:from_file).keys)
      end
    end

    context "with one additional" do
      let(:settings) do
        {
          :ems => {
            :ems_azure => {
              :additional_regions => {
                :"my-custom-region-1" => { :name => "My First Custom Region" }
              }
            }
          }
        }
      end

      it "returns the custom regions" do
        stub_settings(settings)
        expect(described_class.names).to include("my-custom-region-1")
      end
    end

    context "with additional regions and disabled regions" do
      let(:settings) do
        {
          :ems => {
            :ems_azure => {
              :disabled_regions   => ["my-custom-region-2"],
              :additional_regions => {
                :"my-custom-region-1" => { :name => "My First Custom Region" },
                :"my-custom-region-2" => { :name => "My Second Custom Region" }
              }
            }
          }
        }
      end

      it "disabled_regions overrides additional_regions" do
        stub_settings(settings)
        expect(described_class.names).to     include("my-custom-region-1")
        expect(described_class.names).not_to include("my-custom-region-2")
      end
    end
  end
end
