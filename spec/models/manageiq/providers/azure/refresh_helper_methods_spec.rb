require 'azure-armrest'

describe ManageIQ::Providers::Azure::RefreshHelperMethods do
  before do
    @ems_azure = FactoryGirl.create(:ems_azure, :name => 'test', :provider_region => 'eastus')
    @ems_azure.extend(described_class)
    @ems_azure.instance_variable_set(:@ems, @ems_azure)
    allow(Azure::Armrest::VirtualMachineService).to receive(:new).and_return(virtual_machine_service)
  end

  let(:virtual_machine_service) { double }
  let(:virtual_machine_eastus) { Azure::Armrest::VirtualMachine.new(:name => "foo", :location => "eastus") }
  let(:virtual_machine_southindia) { Azure::Armrest::VirtualMachine.new(:name => "bar", :location => "SouthIndia") }

  context "get_resource_group_ems_ref" do
    it "returns the expected value" do
      virtual_machine_eastus.subscription_id = "abc123"
      virtual_machine_eastus.resource_group = "Test_Group"

      expected = "/subscriptions/abc123/resourceGroups/test_group"
      expect(@ems_azure.get_resource_group_ems_ref(virtual_machine_eastus)).to eql(expected)
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
