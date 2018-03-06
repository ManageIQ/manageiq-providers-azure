require 'azure-armrest'
require_relative "azure_refresher_spec_common"

describe ManageIQ::Providers::Azure::CloudManager::EventTargetParser do
  include AzureRefresherSpecCommon

  before(:each) do
    refresh_settings = {
      :inventory_object_refresh => true,
      :inventory_collections    => {
        :saver_strategy => :default,
      },
    }

    @refresh_settings = refresh_settings.merge(:allow_targeted_refresh => true)

    stub_settings_merge(
      :ems_refresh => {
        :azure         => @refresh_settings,
        :azure_network => @refresh_settings,
      }
    )
  end

  before do
    _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone

    @ems = FactoryGirl.create(:ems_azure_with_vcr_authentication, :zone => zone, :provider_region => 'eastus')

    @resource_group    = 'miq-azure-test1'
    @managed_vm        = 'miqazure-linux-managed'
    @device_name       = 'miq-test-rhel1' # Make sure this is running if generating a new cassette.
    @vm_powered_off    = 'miqazure-centos1' # Make sure this is powered off if generating a new cassette.
    @ip_address        = '52.224.165.15' # This will change if you had to restart the @device_name.
    @mismatch_ip       = '52.168.33.118' # This will change if you had to restart the 'miqmismatch1' VM.
    @managed_os_disk   = "miqazure-linux-managed_OsDisk_1_7b2bdf790a7d4379ace2846d307730cd"
    @managed_data_disk = "miqazure-linux-managed-data-disk"
    @template          = nil
    @avail_zone        = nil

    @resource_group_managed_vm = "miq-azure-test4"
  end

  after do
    ::Azure::Armrest::Configuration.clear_caches
  end

  context "NetworkPort events" do
    it "parses networkInterfaces_write_EndRequest event" do
      event_type = "networkInterfaces_write_EndRequest"
      ems_event  = create_ems_event(event_type)

      parsed_targets = described_class.new(ems_event).parse

      expect(parsed_targets.size).to eq(1)
      expect(target_references(parsed_targets)).to(
        match_array(
          [
            [:network_ports, {:ems_ref => "/subscriptions/#{@ems.subscription}/resourceGroups/miq-azure-test1/providers/Microsoft.Network/networkInterfaces/ladas_test"}]
          ]
        )
      )

      assert_target_refreshed_with_right_ems_ref(parsed_targets, event_type)
    end

    it "parses networkInterfaces_delete_EndRequest event" do
      event_type = "networkInterfaces_delete_EndRequest"
      ems_event  = create_ems_event(event_type)

      parsed_targets = described_class.new(ems_event).parse

      expect(parsed_targets.size).to eq(1)
      expect(target_references(parsed_targets)).to(
        match_array(
          [
            [:network_ports, {:ems_ref => "/subscriptions/#{@ems.subscription}/resourceGroups/miq-azure-test1/providers/Microsoft.Network/networkInterfaces/ladas_test"}]
          ]
        )
      )

      # For some reason, interface is still in the Provider's inventory after this event
      assert_target_refreshed_with_right_ems_ref(parsed_targets, event_type, true)
    end
  end

  context "VM events" do
    it "parses virtualMachines_delete_EndRequest event" do
      event_type = "virtualMachines_delete_EndRequest"
      ems_event  = create_ems_event(event_type)

      parsed_targets = described_class.new(ems_event).parse

      expect(parsed_targets.size).to eq(1)
      expect(target_references(parsed_targets)).to(
        match_array(
          [
            [:vms, {:ems_ref => "#{@ems.subscription}\\miq-azure-test1\\microsoft.compute/virtualmachines\\ladas_test"}]
          ]
        )
      )

      assert_target_refreshed_with_right_ems_ref(parsed_targets, event_type, true)
    end

    it "parses virtualMachines_deallocate_EndRequest event" do
      event_type = "virtualMachines_deallocate_EndRequest"
      ems_event  = create_ems_event(event_type)

      parsed_targets = described_class.new(ems_event).parse

      expect(parsed_targets.size).to eq(1)
      expect(target_references(parsed_targets)).to(
        match_array(
          [
            [:vms, {:ems_ref => "#{@ems.subscription}\\miq-azure-test1\\microsoft.compute/virtualmachines\\ladas_test"}]
          ]
        )
      )

      assert_target_refreshed_with_right_ems_ref(parsed_targets, event_type)
    end

    it "parses virtualMachines_restart_EndRequest event" do
      event_type = "virtualMachines_restart_EndRequest"
      ems_event  = create_ems_event(event_type)

      parsed_targets = described_class.new(ems_event).parse

      expect(parsed_targets.size).to eq(1)
      expect(target_references(parsed_targets)).to(
        match_array(
          [
            [:vms, {:ems_ref => "#{@ems.subscription}\\miq-azure-test1\\microsoft.compute/virtualmachines\\ladas_test"}]
          ]
        )
      )

      assert_target_refreshed_with_right_ems_ref(parsed_targets, event_type)
    end

    it "parses virtualMachines_start_EndRequest event" do
      event_type = "virtualMachines_start_EndRequest"
      ems_event  = create_ems_event(event_type)

      parsed_targets = described_class.new(ems_event).parse

      expect(parsed_targets.size).to eq(1)
      expect(target_references(parsed_targets)).to(
        match_array(
          [
            [:vms, {:ems_ref => "#{@ems.subscription}\\miq-azure-test1\\microsoft.compute/virtualmachines\\ladas_test"}]
          ]
        )
      )

      assert_target_refreshed_with_right_ems_ref(parsed_targets, event_type)
    end

    it "parses virtualMachines_powerOff_EndRequest event" do
      event_type = "virtualMachines_deallocate_EndRequest"
      ems_event  = create_ems_event(event_type)

      parsed_targets = described_class.new(ems_event).parse

      expect(parsed_targets.size).to eq(1)
      expect(target_references(parsed_targets)).to(
        match_array(
          [
            [:vms, {:ems_ref => "#{@ems.subscription}\\miq-azure-test1\\microsoft.compute/virtualmachines\\ladas_test"}]
          ]
        )
      )

      assert_target_refreshed_with_right_ems_ref(parsed_targets, event_type)
    end

    it "parses virtualMachines_write_EndRequest event" do
      event_type = "virtualMachines_write_EndRequest"
      ems_event  = create_ems_event(event_type)

      parsed_targets = described_class.new(ems_event).parse

      expect(parsed_targets.size).to eq(1)
      expect(target_references(parsed_targets)).to(
        match_array(
          [
            [:vms, {:ems_ref => "#{@ems.subscription}\\miq-azure-test1\\microsoft.compute/virtualmachines\\ladas_test"}]
          ]
        )
      )

      assert_target_refreshed_with_right_ems_ref(parsed_targets, event_type)
    end
  end

  context "CloudNetwork events" do
    it "parses virtualNetworks_write_EndRequest event" do
      event_type = "virtualNetworks_write_EndRequest"
      ems_event  = create_ems_event(event_type)

      parsed_targets = described_class.new(ems_event).parse

      expect(parsed_targets.size).to eq(1)
      expect(target_references(parsed_targets)).to(
        match_array(
          [
            [:cloud_networks, {:ems_ref => "/subscriptions/#{@ems.subscription}/resourceGroups/miq-azure-test1/providers/Microsoft.Network/virtualNetworks/ladas_test"}]
          ]
        )
      )

      assert_target_refreshed_with_right_ems_ref(parsed_targets, event_type)
    end
  end

  context "SecurityGroup events" do
    it "parses networkSecurityGroups_write_EndRequest event" do
      event_type = "networkSecurityGroups_write_EndRequest"
      ems_event  = create_ems_event(event_type)

      parsed_targets = described_class.new(ems_event).parse

      expect(parsed_targets.size).to eq(1)
      expect(target_references(parsed_targets)).to(
        match_array(
          [
            [:security_groups, {:ems_ref => "/subscriptions/#{@ems.subscription}/resourceGroups/miq-azure-test1/providers/Microsoft.Network/networkSecurityGroups/ladas_test"}]
          ]
        )
      )

      assert_target_refreshed_with_right_ems_ref(parsed_targets, event_type)
    end
  end

  context "LoadBalancer events" do
    it "parses loadBalancers_write_EndRequest event" do
      event_type = "loadBalancers_write_EndRequest"
      ems_event  = create_ems_event(event_type)

      parsed_targets = described_class.new(ems_event).parse

      expect(parsed_targets.size).to eq(1)
      expect(target_references(parsed_targets)).to(
        match_array(
          [
            [:load_balancers, {:ems_ref => "/subscriptions/#{@ems.subscription}/resourceGroups/miq-azure-test1/providers/Microsoft.Network/loadBalancers/ladas_test"}]
          ]
        )
      )

      assert_target_refreshed_with_right_ems_ref(parsed_targets, event_type)
    end
  end

  context "OrchestrationStack events" do
    it "parses deployments_write_EndRequest event" do
      event_type = "deployments_write_EndRequest"
      ems_event  = create_ems_event(event_type)

      parsed_targets = described_class.new(ems_event).parse

      expect(parsed_targets.size).to eq(1)
      expect(target_references(parsed_targets)).to(
        match_array(
          [
            [:orchestration_stacks, {:ems_ref => "/subscriptions/#{@ems.subscription}/resourceGroups/miq-azure-test1/providers/Microsoft.Resources/deployments/Microsoft.LoadBalancer-20180305183523"}]
          ]
        )
      )

      assert_target_refreshed_with_right_ems_ref(parsed_targets, event_type)
    end
  end

  context "FloatingIp events" do
    it "parses publicIPAddresses_write_EndRequest event" do
      event_type = "publicIPAddresses_write_EndRequest"
      ems_event  = create_ems_event(event_type)

      parsed_targets = described_class.new(ems_event).parse

      expect(parsed_targets.size).to eq(1)
      expect(target_references(parsed_targets)).to(
        match_array(
          [
            [:floating_ips, {:ems_ref => "/subscriptions/#{@ems.subscription}/resourceGroups/miq-azure-test1/providers/Microsoft.Network/publicIPAddresses/ladas_test"}]
          ]
        )
      )

      assert_target_refreshed_with_right_ems_ref(parsed_targets, event_type)
    end
  end

  context "Image events" do
    it "parses images_write_EndRequest event" do
      event_type = "images_write_EndRequest"
      ems_event  = create_ems_event(event_type)

      parsed_targets = described_class.new(ems_event).parse

      expect(parsed_targets.size).to eq(1)
      expect(target_references(parsed_targets)).to(
        match_array(
          [
            [:miq_templates, {:ems_ref => "/subscriptions/#{@ems.subscription.downcase}/resourcegroups/miq-azure-test1/providers/microsoft.compute/images/ladas_test"}]
          ]
        )
      )

      assert_target_refreshed_with_right_ems_ref(parsed_targets, event_type)
    end
  end

  def assert_target_refreshed_with_right_ems_ref(parsed_targets, suffix, expect_to_be_nil = false)
    # Due to non trivial transformation of ems_ref in several places of refresh parser, lets test actual targeted
    # refresh leads to having the object in the DB.
    refresh_with_cassette(parsed_targets, "_event_target_parser/#{suffix}")
    parsed_targets.each do |target|
      if expect_to_be_nil
        expect(fetch_record(target)).to be_nil, "Target :#{target.association} with manager_ref: #{target.manager_ref} is supossed to be soft deleted"
      else
        expect(fetch_record(target)).not_to be_nil, "Target :#{target.association} with manager_ref: #{target.manager_ref} was not refreshed"
      end
    end
  end

  def fetch_record(target)
    manager = case target.association
              when :load_balancers
                target.manager.network_manager
              else
                target.manager
              end
    manager.public_send(target.association).find_by(target.manager_ref)
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
