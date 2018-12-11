require 'azure-armrest'

describe ManageIQ::Providers::Azure::CloudManager::EventTargetParser do
  let(:resource_group) { 'miq-azure-test1' }
  let(:event_variant) { }

  before do
    _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone

    @ems = FactoryBot.create(:ems_azure_with_vcr_authentication, :zone => zone, :provider_region => 'eastus')
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
    let(:expected_ems_ref) { "#{@ems.subscription}/#{resource_group}/microsoft.compute/virtualmachines/test-vm" }

    it_behaves_like "parses_event", "virtualMachines_deallocate_EndRequest"
    it_behaves_like "parses_event", "virtualMachines_delete_EndRequest"
    it_behaves_like "parses_event", "virtualMachines_generalize_EndRequest"
    it_behaves_like "parses_event", "virtualMachines_restart_EndRequest"
    it_behaves_like "parses_event", "virtualMachines_start_EndRequest"
    it_behaves_like "parses_event", "virtualMachines_powerOff_EndRequest"
    it_behaves_like "parses_event", "virtualMachines_write_EndRequest"
  end

  context "VM lock events" do
    let(:klass) { :vms }
    let(:expected_ems_ref) { "#{@ems.subscription}/#{resource_group}/microsoft.authorization/locks/test-lock" }

    it_behaves_like "parses_event", "locks_delete_EndRequest"
    it_behaves_like "parses_event", "locks_write_EndRequest"
  end

  context "CloudNetwork events" do
    let(:klass) { :cloud_networks }
    let(:expected_ems_ref) { "/subscriptions/#{@ems.subscription}/resourceGroups/#{resource_group}/providers/Microsoft.Network/virtualNetworks/test-vnet" }

    it_behaves_like "parses_event", "virtualNetworks_delete_EndRequest"
    it_behaves_like "parses_event", "virtualNetworks_write_EndRequest"
    it_behaves_like "parses_event", "virtualNetworks_subnets_EndRequest"

    context do
      let(:event_variant) { :downcase }

      it_behaves_like "parses_event", "virtualnetworks_delete_EndRequest"
      it_behaves_like "parses_event", "virtualnetworks_write_EndRequest"
      it_behaves_like "parses_event", "virtualnetworks_subnets_EndRequest"
    end
  end

  context "SecurityGroup events" do
    let(:klass) { :security_groups }
    let(:expected_ems_ref) { "/subscriptions/#{@ems.subscription}/resourceGroups/#{resource_group}/providers/Microsoft.Network/networkSecurityGroups/test-nsg" }

    it_behaves_like "parses_event", "networkSecurityGroups_delete_EndRequest"
    it_behaves_like "parses_event", "networkSecurityGroups_write_EndRequest"
    it_behaves_like "parses_event", "networkSecurityGroups_securityRules_EndRequest"
  end

  context "LoadBalancer events" do
    let(:klass) { :load_balancers }
    let(:expected_ems_ref) { "/subscriptions/#{@ems.subscription}/resourceGroups/#{resource_group}/providers/Microsoft.Network/loadBalancers/test-lb" }

    it_behaves_like "parses_event", "loadBalancers_delete_EndRequest"
    it_behaves_like "parses_event", "loadBalancers_write_EndRequest"
  end

  context "OrchestrationStack events" do
    let(:klass) { :orchestration_stacks }
    let(:expected_ems_ref) { "/subscriptions/#{@ems.subscription}/resourceGroups/#{resource_group}/providers/Microsoft.Resources/deployments/Microsoft.LoadBalancer-20180305183523" }

    it_behaves_like "parses_event", "deployments_write_EndRequest"

    # TODO: Low priority events, broken resource_id transformation
    # it_behaves_like "parses_event", "deployments_exportTemplate_EndRequest"
    # it_behaves_like "parses_event", "deployments_validate_EndRequest"
  end

  context "FloatingIp events" do
    let(:klass) { :floating_ips }
    let(:expected_ems_ref) { "/subscriptions/#{@ems.subscription}/resourceGroups/#{resource_group}/providers/Microsoft.Network/publicIPAddresses/test-ip" }

    it_behaves_like "parses_event", "publicIPAddresses_delete_EndRequest"
    it_behaves_like "parses_event", "publicIPAddresses_write_EndRequest"

    context do
      let(:event_variant) { :downcase }

      it_behaves_like "parses_event", "publicIpAddresses_delete_EndRequest"
      it_behaves_like "parses_event", "publicIpAddresses_write_EndRequest"
    end
  end

  context "Image events" do
    let(:klass) { :miq_templates }
    let(:expected_ems_ref) { "/subscriptions/#{@ems.subscription.downcase}/resourcegroups/#{resource_group}/providers/microsoft.compute/images/test-img" }

    it_behaves_like "parses_event", "images_delete_EndRequest"
    it_behaves_like "parses_event", "images_write_EndRequest"
  end

  context "Resource groups" do
    let(:klass) { :resource_groups }
    let(:expected_ems_ref) { "/subscriptions/#{@ems.subscription}/resourceGroups/#{resource_group}" }

    it_behaves_like "parses_event", "subscriptions_resourceGroups_EndRequest"
    it_behaves_like "parses_event", "subscriptions_resourcegroups_EndRequest" do
      let(:event_variant) { :downcase }
    end
  end

  context "Disks" do
    let(:klass) { :__unused }
    let(:expected_ems_ref) { "/subscriptions/#{@ems.subscription}/resourceGroups/#{resource_group.upcase}/providers/Microsoft.Compute/disks/test-vm_OsDisk_1_3896596a3c8b449b85f9b0e512995d39" }

    it_behaves_like "parses_event", "disks_delete_EndRequest"
    it_behaves_like "parses_event", "disks_write_EndRequest"
  end

  context "Snapshots" do
    let(:klass) { :__unused }
    let(:expected_ems_ref) { "/subscriptions/#{@ems.subscription}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/snapshots/test-vm_OsDisk_1_3896596a3c8b449b85f9b0e512995d39-snapshot" }

    it_behaves_like "parses_event", "snapshots_delete_EndRequest"
    it_behaves_like "parses_event", "snapshots_write_EndRequest"
  end

  context "Storage Accounts" do
    let(:klass) { :__unused }
    let(:expected_ems_ref) { "/subscriptions/#{@ems.subscription}/resourceGroups/#{resource_group}/providers/Microsoft.Storage/storageAccounts/test-storageaccount" }

    it_behaves_like "parses_event", "storageAccounts_delete_EndRequest"
    it_behaves_like "parses_event", "storageAccounts_write_EndRequest"
  end

  context "Availability Sets" do
    let(:klass) { :__unused }
    let(:expected_ems_ref) { "/subscriptions/#{@ems.subscription}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/availabilitySets/test-availset" }

    it_behaves_like "parses_event", "availabilitySets_delete_EndRequest"
    it_behaves_like "parses_event", "availabilitySets_write_EndRequest"
  end

  def target_references(parsed_targets)
    parsed_targets.map { |x| [x.association, x.manager_ref] }.uniq
  end

  def event(path)
    path += "_#{event_variant}" if event_variant
    event = File.read(File.join(File.dirname(__FILE__), "/event_catcher/event_data/#{path}.json"))
    event.gsub!("AZURE_SUBSCRIPTION_ID", @ems.subscription) # put back the right subscription
    JSON.parse(event)
  end

  def create_ems_event(path)
    event_hash = ManageIQ::Providers::Azure::CloudManager::EventParser.event_to_hash(event(path), @ems.id)
    EmsEvent.add(@ems.id, event_hash)
  end
end
