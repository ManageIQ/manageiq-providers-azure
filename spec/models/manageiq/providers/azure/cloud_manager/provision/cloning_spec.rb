require 'azure-armrest'

describe ManageIQ::Providers::Azure::CloudManager::Provision::Cloning do
  let(:template) { FactoryBot.create(:azure_image, :ext_management_system => ems) }
  let(:provision) { FactoryBot.create(:miq_provision_azure, :options => {:src_vm_id => template.id}, :miq_request => miq_request) }
  let(:configuration) { double("azure armrest configuration") }
  let(:vms) { double("virtual machine service") }
  let(:ems) { FactoryBot.create(:ems_azure_with_authentication) }
  let(:ip_address_service) { double('ip address service') }
  let(:public_ip) { double('public ip') }
  let(:network_interface) { double('network interface') }
  let(:nic_service) { double("nic service") }
  let(:nic_id) { '/subscriptions/xyz/resourceGroups/foo/providers/Microsoft.Network/networkInterfaces/foo_nic' }
  let(:miq_request) { FactoryBot.create(:miq_provision_request) }


  context "associated_nic" do
    before do
      @floating_ip = FactoryBot.create(:floating_ip_azure)
      @network_port = FactoryBot.create(:network_port_azure)
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
      @floating_ip = FactoryBot.create(:floating_ip_azure)
      @network_port = FactoryBot.create(:network_port_azure)
      @resource_group = FactoryBot.create(:azure_resource_group)

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

  context "start_clone_task" do
    before do
      resource_group = FactoryBot.create(:azure_resource_group)
      dest_name = "test"
      clone_options = {clone_options: {name: "test-name", location: "germanycentralwest"}}

      allow(Azure::Armrest::Network::IpAddressService).to receive(:new).and_return(ip_address_service)
      allow(Azure::Armrest::Network::NetworkInterfaceService).to receive(:new).and_return(nic_service)
      allow(Azure::Armrest::Configuration).to receive(:new).and_return(configuration)
      allow(Azure::Armrest::VirtualMachineService).to receive(:new).and_return(vms)

      allow(provision).to receive(:resource_group).and_return(resource_group)
      allow(provision).to receive(:dest_name).and_return(dest_name)
      allow(provision).to receive(:phase_context).and_return(clone_options)
      allow(provision).to receive(:requeue_phase)

      allow(vms).to receive(:create).and_raise(Azure::Armrest::BadRequestException.new('errors', 'details', 'info'))
      allow(ip_address_service).to receive(:get).and_return(public_ip)
      allow(nic_service).to receive(:get).and_return(network_interface)
      
      allow(nic_service).to receive(:delete)
      allow(ip_address_service).to receive(:delete)
    end
  
    it 'deletes the public IP and network interface when a BadRequestException is raised' do
      provision.start_clone_task
      expect(ip_address_service).to have_received(:delete)
      expect(nic_service).to have_received(:delete)      
    end

    it 'phase_context is requeued properly after BadRequestException' do
      allow(nic_service).to receive(:delete).and_raise(Azure::Armrest::BadRequestException.new('errors', 'details', 'info'))
      provision.start_clone_task
      expect(provision).to have_received(:requeue_phase).with(3.minutes)
    end

    it 'phase_context errors are properly set after BadRequestException' do
      allow(nic_service).to receive(:delete).and_raise(Azure::Armrest::BadRequestException.new('errors', 'details', 'info'))
      provision.start_clone_task
      expect(provision.phase_context[:exception_class]).to eq('Azure::Armrest::BadRequestException')
      expect(provision.phase_context[:exception_message]).to eq('details')
    end
  end
end
