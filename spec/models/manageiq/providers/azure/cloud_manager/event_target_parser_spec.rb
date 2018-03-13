require 'azure-armrest'

describe ManageIQ::Providers::Azure::CloudManager::EventTargetParser do
  let(:resource_group) { 'miq-azure-test1' }

  before do
    _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone

    @ems = FactoryGirl.create(:ems_azure_with_vcr_authentication, :zone => zone, :provider_region => 'eastus')
  end

  shared_examples "parses_event" do |event_type|
    subject { described_class.new(create_ems_event(event_type)).parse }
    let(:expected_references) do
      [
        [klass, {:ems_ref => expected_ems_ref}]
      ]
    end

    it "parses #{event_type} event" do
      expect(subject.size).to eq(1)
      expect(target_references(subject)).to match_array(expected_references)
    end
  end

  context "NetworkPort events" do
    let(:klass) { :network_ports }
    let(:expected_ems_ref) { "/subscriptions/#{@ems.subscription}/resourceGroups/#{resource_group}/providers/Microsoft.Network/networkInterfaces/test-vnet-port" }

    it_behaves_like "parses_event", "networkInterfaces_delete_EndRequest"
    it_behaves_like "parses_event", "networkInterfaces_write_EndRequest"
  end

  context "VM events" do
    let(:klass) { :vms }
    let(:expected_ems_ref) { "#{@ems.subscription}\\#{resource_group}\\microsoft.compute/virtualmachines\\test-vm" }

    it_behaves_like "parses_event", "virtualMachines_delete_EndRequest"
    it_behaves_like "parses_event", "virtualMachines_deallocate_EndRequest"
    it_behaves_like "parses_event", "virtualMachines_restart_EndRequest"
    it_behaves_like "parses_event", "virtualMachines_start_EndRequest"
    it_behaves_like "parses_event", "virtualMachines_powerOff_EndRequest"
    it_behaves_like "parses_event", "virtualMachines_write_EndRequest"
  end

  context "CloudNetwork events" do
    let(:klass) { :cloud_networks }
    let(:expected_ems_ref) { "/subscriptions/#{@ems.subscription}/resourceGroups/miq-azure-test1/providers/Microsoft.Network/virtualNetworks/test-vnet" }

    it_behaves_like "parses_event", "virtualNetworks_write_EndRequest" do
    end
  end

  context "SecurityGroup events" do
    let(:klass) { :security_groups }
    let(:expected_ems_ref) { "/subscriptions/#{@ems.subscription}/resourceGroups/#{resource_group}/providers/Microsoft.Network/networkSecurityGroups/test-nsg" }

    it_behaves_like "parses_event", "networkSecurityGroups_write_EndRequest"
  end

  context "LoadBalancer events" do
    let(:klass) { :load_balancers }
    let(:expected_ems_ref) { "/subscriptions/#{@ems.subscription}/resourceGroups/#{resource_group}/providers/Microsoft.Network/loadBalancers/test-lb" }

    it_behaves_like "parses_event", "loadBalancers_write_EndRequest"
  end

  context "OrchestrationStack events" do
    let(:klass) { :orchestration_stacks }
    let(:expected_ems_ref) { "/subscriptions/#{@ems.subscription}/resourceGroups/#{resource_group}/providers/Microsoft.Resources/deployments/Microsoft.LoadBalancer-20180305183523" }

    it_behaves_like "parses_event", "deployments_write_EndRequest"
  end

  context "FloatingIp events" do
    let(:klass) { :floating_ips }
    let(:expected_ems_ref) { "/subscriptions/#{@ems.subscription}/resourceGroups/#{resource_group}/providers/Microsoft.Network/publicIPAddresses/test-ip" }

    it_behaves_like "parses_event", "publicIPAddresses_write_EndRequest"
  end

  context "Image events" do
    let(:klass) { :miq_templates }
    let(:expected_ems_ref) { "/subscriptions/#{@ems.subscription.downcase}/resourcegroups/#{resource_group}/providers/microsoft.compute/images/test-img" }

    it_behaves_like "parses_event", "images_write_EndRequest"
  end

  def target_references(parsed_targets)
    parsed_targets.map { |x| [x.association, x.manager_ref] }.uniq
  end

  def event(path)
    event = File.read(File.join(File.dirname(__FILE__), "/event_catcher/event_data/#{path}.json"))
    event.gsub!("AZURE_SUBSCRIPTION_ID", @ems.subscription) # put back the right subscription
    JSON.parse(event)
  end

  def create_ems_event(path)
    event_hash = ManageIQ::Providers::Azure::CloudManager::EventParser.event_to_hash(event(path), @ems.id)
    EmsEvent.add(@ems.id, event_hash)
  end
end
