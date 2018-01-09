require 'azure-armrest'

describe ManageIQ::Providers::Azure::CloudManager::Provision::Cloning do
  let(:provision) { ManageIQ::Providers::Azure::CloudManager::Provision.new }
  let(:ems) { FactoryGirl.create(:ems_azure_with_authentication) }
  let(:ip_address_service) { double('ip address service') }
  let(:nic_id) { '/subscriptions/xyz/resourceGroups/foo/providers/Microsoft.Network/networkInterfaces/foo_nic' }

  context "associated_nic" do
    before do
      @floating_ip = FactoryGirl.create(:floating_ip_azure)
      @network_port = FactoryGirl.create(:network_port_azure)
    end

    it "returns nil if floating ip is not found" do
      expect(provision.associated_nic).to be_nil
    end

    it "returns nil if floating ip is found but there is no network_port" do
      allow(provision).to receive(:floating_ip).and_return(@floating_ip)
      expect(provision.associated_nic).to be_nil
    end

    it "returns expected ems_ref value if network_port is defined" do
      @floating_ip.network_port = @network_port
      allow(provision).to receive(:floating_ip).and_return(@floating_ip)
      expect(provision.associated_nic).to eql(@network_port.ems_ref)
    end
  end

  context "create_nic" do
    before do
      @floating_ip = FactoryGirl.create(:floating_ip_azure)
      @network_port = FactoryGirl.create(:network_port_azure)
      @resource_group = FactoryGirl.create(:azure_resource_group)

      nic_service = double("nic service")

      nic_options = {
        :id         => nic_id,
        :location   => 'eastus',
        :properties => {
          :ipConfigurations => [
            :name       => 'foo',
            :properties => {
              :subnet          => {:id => 'bar'},
              :publicIPAddress => '1.2.3.4'
            }
          ]
        }
      }

      ip_options = {
        :name       => "foo",
        :id         => "/subscriptions/xyz/resourceGroups/aaa/providers/Microsoft.Network/publicIPAddresses/foo",
        :location   => "westus2",
        :properties => {
          :provisioningState        => "Succeeded",
          :resourceGuid             => "xyz",
          :ipAddress                => "1.2.3.4",
          :publicIPAddressVersion   => "IPv4",
          :publicIPAllocationMethod => "Dynamic",
          :idleTimeoutInMinutes     => 4,
          :ipConfiguration          => {
            :id => "/subscriptions/xyz/resourceGroups/aaa/providers/Microsoft.Network/networkInterfaces/some_nic/ipConfigurations/ipconfig1"
          }
        },
        :type       => "Microsoft.Network/publicIPAddresses",
        :sku        => { :name => "Basic" }
      }

      @nic_object = Azure::Armrest::Network::NetworkInterface.new(nic_options)
      @public_ip  = Azure::Armrest::Network::IpAddress.new(ip_options)

      allow(provision).to receive(:source).and_return(ems)
      allow(provision).to receive(:build_nic_options).and_return(nic_options)
      allow(provision).to receive(:resource_group).and_return(@resource_group)
      allow(provision).to receive(:region).and_return('westus2')

      allow(ManageIQ::Providers::Azure::CloudManager).to receive(:raw_connect).and_return(double)
      allow(Azure::Armrest::Network::IpAddressService).to receive(:new).and_return(ip_address_service)
      allow(Azure::Armrest::Network::NetworkInterfaceService).to receive(:new).and_return(nic_service)

      allow(nic_service).to receive(:create).and_return(@nic_object)
    end

    it "uses the existing public IP if possible" do
      allow(provision).to receive(:floating_ip).and_return(@floating_ip)
      allow(@floating_ip).to receive(:ems_ref).and_return('xyz')
      allow(ip_address_service).to receive(:get_by_id).and_return(@public_ip)

      expect(provision.create_nic).to eql(@nic_object.id)
    end

    it "creates a new public IP if the existing one cannot be found" do
      allow(provision).to receive(:floating_ip).and_return(@floating_ip)
      allow(@floating_ip).to receive(:ems_ref).and_return('xyz')
      allow(ip_address_service).to receive(:get_by_id).and_raise(Azure::Armrest::NotFoundException.new('x', 'y', 'z'))
      allow(ip_address_service).to receive(:create).and_return(@public_ip)

      expect(provision.create_nic).to eql(@nic_object.id)
    end

    it "creates a new public IP if there is no ems_ref for the floating IP" do
      allow(provision).to receive(:floating_ip).and_return(@floating_ip)
      allow(@floating_ip).to receive(:ems_ref).and_return(nil)
      allow(ip_address_service).to receive(:create).and_return(@public_ip)

      expect(provision.create_nic).to eql(@nic_object.id)
    end

    it "creates a NIC with a private IP if its argument is false" do
      expect(provision.create_nic(false)).to eql(@nic_object.id)
    end
  end
end
