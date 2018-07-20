require 'azure-armrest'

describe ManageIQ::Providers::Azure::RefreshHelperMethods do
  before do
    @ems_azure = FactoryGirl.create(:ems_azure, :name => 'test', :provider_region => 'eastus')
    @ems_azure.extend(described_class)
    @ems_azure.instance_variable_set(:@ems, @ems_azure)
    allow(Azure::Armrest::VirtualMachineService).to receive(:new).and_return(virtual_machine_service)
  end

  let(:virtual_machine_service) { double }
  let(:resource_provider_service) { double }
  let(:configuration) { double }
  let(:virtual_machine_eastus) { Azure::Armrest::VirtualMachine.new(:name => "foo", :location => "eastus") }
  let(:virtual_machine_southindia) { Azure::Armrest::VirtualMachine.new(:name => "bar", :location => "SouthIndia") }

  context "valid_api_version" do
    before do
      allow(Azure::Armrest::Configuration).to receive(:new).and_return(configuration)
      allow(Azure::Armrest::ResourceProviderService).to receive(:new).and_return(resource_provider_service)
      allow(resource_provider_service).to receive(:api_version=).with('2016-09-01').and_return('2016-09-01')
      allow(@ems_azure.cached_resource_provider_service(configuration)) { resource_provider_service }
      allow(virtual_machine_service).to receive(:service_name).and_return('virtualMachines')
      allow(virtual_machine_service).to receive(:provider).and_return('Microsoft.Compute')
      @valid_list = ['2018-06-01', '2018-04-01', '2017-12-01', '2017-03-30']
    end

    it "returns the settings value if valid" do
      allow(@ems_azure.cached_resource_provider_service(configuration)).to receive(:supported?).and_return(true)
      allow(@ems_azure.cached_resource_provider_service(configuration)).to receive(:list_api_versions).and_return(@valid_list)
      expect(@ems_azure.valid_api_version(configuration, virtual_machine_service, :virtual_machine)).to eql('2017-12-01')
    end

    it "returns a valid value if the settings value is invalid" do
      allow(Settings.ems.ems_azure.api_versions).to receive(:[]).with(:virtual_machine).and_return('2018-01-01')
      allow(@ems_azure.cached_resource_provider_service(configuration)).to receive(:supported?).and_return(true)
      allow(@ems_azure.cached_resource_provider_service(configuration)).to receive(:list_api_versions).and_return(@valid_list)
      expect(@ems_azure.valid_api_version(configuration, virtual_machine_service, :virtual_machine)).to eql('2018-06-01')
    end

    it "returns the settings value if the service is unsupported" do
      allow(Settings.ems.ems_azure.api_versions).to receive(:[]).with(:virtual_machine).and_return('2018-01-01')
      allow(@ems_azure.cached_resource_provider_service(configuration)).to receive(:supported?).and_return(false)
      expect(@ems_azure.valid_api_version(configuration, virtual_machine_service, :virtual_machine)).to eql('2018-01-01')
    end
  end

  context "get_resource_group_ems_ref" do
    it "returns the expected value" do
      virtual_machine_eastus.subscription_id = "abc123"
      virtual_machine_eastus.resource_group = "Test_Group"

      expected = "/subscriptions/abc123/resourcegroups/test_group"
      expect(@ems_azure.get_resource_group_ems_ref(virtual_machine_eastus)).to eql(expected)
    end
  end

  context "build_image_name" do
    it "removes ./ from image names" do
      image = FactoryGirl.create(:azure_image, :name => './foo', :location => 'westus', :vendor => 'azure')
      expect(@ems_azure.build_image_name(image)).to eql('foo')
    end

    it "does not affect images that do not have a ./ in them" do
      image = FactoryGirl.create(:azure_image, :name => 'foo', :location => 'westus', :vendor => 'azure')
      expect(@ems_azure.build_image_name(image)).to eql('foo')
    end
  end

  context "gather_data_for_region" do
    it "requires a service name" do
      expect { @ems_azure.gather_data_for_this_region }.to raise_error(ArgumentError)
    end

    it "accepts an optional method name" do
      allow(virtual_machine_service).to receive(:list_all).and_return([])
      expect(@ems_azure.gather_data_for_this_region(virtual_machine_service, 'list_all')).to eql([])
    end

    it "returns the expected results for matching location" do
      allow(virtual_machine_service).to receive(:list_all).and_return([virtual_machine_eastus])
      expect(@ems_azure.gather_data_for_this_region(virtual_machine_service, 'list_all')).to eql([virtual_machine_eastus])
    end

    it "returns the expected results for non-matching location" do
      allow(virtual_machine_service).to receive(:list_all).and_return([virtual_machine_southindia])
      expect(@ems_azure.gather_data_for_this_region(virtual_machine_service, 'list_all')).to eql([])
    end

    it "ignores case when searching for matching locations" do
      @ems_azure.provider_region = 'southindia'
      allow(virtual_machine_service).to receive(:list_all).and_return([virtual_machine_southindia])
      expect(@ems_azure.gather_data_for_this_region(virtual_machine_service, 'list_all')).to eql([virtual_machine_southindia])
    end
  end
end
