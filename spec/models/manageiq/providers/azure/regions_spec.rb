describe ManageIQ::Providers::Azure::Regions do

  context "region list" do
    # You can get these by running Azure::Armrest::ArmrestService#list_locations
    def azure_regions
      %w(
        australiaeast australiasoutheast brazilsouth canadacentral canadaeast
        centralindia centralus eastasia eastus eastus2 japaneast japanwest
        koreacentral koreasouth northcentralus northeurope southcentralus
        southeastasia southindia uksouth ukwest westcentralus westeurope
        westindia westus westus2
      )
    end

    it "has all the regions" do
      defined_regions = described_class.regions.map { |_name, config| config[:name] }

      # We cheat a bit here because our sub doesn't have access to some regions
      defined_regions.reject! { |region| region =~ /usgov|china|germany/i }

      expect(azure_regions).to match_array(defined_regions)
    end
  end

  context "disable regions via Settings" do
    it "contains gov_cloud without it being disabled" do
      allow(Settings.ems.ems_azure).to receive(:disabled_regions).and_return([])
      expect(described_class.names).to include("usgoviowa")
    end

    it "contains gov_cloud without disabled_regions being set at all - for backwards compatibility" do
      allow(Settings.ems).to receive(:ems_azure).and_return(nil)
      expect(described_class.names).to include("usgoviowa")
    end

    it "does not contain some regions that are disabled" do
      allow(Settings.ems.ems_azure).to receive(:disabled_regions).and_return(['usgoviowa'])
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
        expect(described_class.names).to eql(described_class::REGIONS.keys)
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
