require 'azure-armrest'
require_relative "azure_refresher_spec_common"

describe ManageIQ::Providers::Azure::CloudManager::Refresher do
  include AzureRefresherSpecCommon

  AzureRefresherSpecCommon::ALL_GRAPH_REFRESH_SETTINGS.each do |refresh_settings|
    context "with settings #{refresh_settings}" do
      before(:each) do
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
        @ip_address        = '52.224.165.15'  # This will change if you had to restart the @device_name.
        @mismatch_ip       = '13.92.63.10'    # This will change if you had to restart the 'miqmismatch1' VM.
        @managed_os_disk   = "miqazure-linux-managed_OsDisk_1_7b2bdf790a7d4379ace2846d307730cd"
        @managed_data_disk = "miqazure-linux-managed-data-disk"
        @template          = nil
        @avail_zone        = nil

        @resource_group_managed_vm = "miq-azure-test4"
      end

      after do
        ::Azure::Armrest::Configuration.clear_caches
      end

      context "with full refresh preceding targeted refresh" do
        before :each do
          setup_ems_and_cassette(@refresh_settings)
          @inventory_before = serialize_inventory
          assert_all
          ::Azure::Armrest::Configuration.clear_caches
        end

        after :each do
          assert_all

          inventory_after = serialize_inventory
          assert_models_not_changed(@inventory_before, inventory_after)
        end

        it ".ems_type" do
          expect(described_class.ems_type).to eq(:azure)
        end

        it "will refresh powered on VM" do
          refresh_with_cassette([vm_powered_on_target], "_targeted_scope/powered_on_vm_refresh")
        end

        it "will refresh powered off VM" do
          refresh_with_cassette([vm_powered_off_target], "_targeted_scope/powered_off_vm_refresh")
        end

        it "will refresh VM with managed disk" do
          refresh_with_cassette([vm_with_managed_disk_target], "_targeted_scope/vm_with_managed_disk_refresh")
        end

        it "will refresh multiple objects at once" do
          targets = [
            vm_with_managed_disk_target,
            vm_powered_on_target,
            vm_powered_off_target,
            non_existent_vm_target,
            lb_target,
            non_existent_lb_target,
            network_port_target,
            non_existent_network_port_target,
            cloud_network_target,
            non_existent_cloud_network_target,
            security_group_target,
            non_existent_security_group_target,
            resource_group_target,
            non_existent_resource_group_target,
            non_existent_orchestration_stack_target,
            flavor_target,
            non_existent_flavor_target
          ]

          refresh_with_cassette(targets, "_targeted_scope/multiple_targets_refresh")
        end

        it "will refresh cloud network" do
          refresh_with_cassette([cloud_network_target], "_targeted_scope/cloud_network_refresh")
        end

        it "will refresh resource group target" do
          refresh_with_cassette([resource_group_target], "_targeted_scope/resource_group_refresh")
        end

        it "will refresh security group target" do
          refresh_with_cassette([security_group_target], "_targeted_scope/security_group_refresh")
        end

        it "will refresh network_port target" do
          refresh_with_cassette([network_port_target], "_targeted_scope/network_port_refresh")
        end

        it "will refresh orchestration stack" do
          refresh_with_cassette([parent_orchestration_stack_target], "_targeted_scope/orchestration_stack_refresh")
        end

        it "will refresh orchestration stack followed by Vm refresh" do
          refresh_with_cassette([parent_orchestration_stack_target], "_targeted_scope/orchestration_stack_refresh")
          ::Azure::Armrest::Configuration.clear_caches
          refresh_with_cassette([child_orchestration_stack_vm_target], "_targeted_scope/orchestration_stack_vm_refresh")
        end

        it "will refresh orchestration stack with vms" do
          refresh_with_cassette([parent_orchestration_stack_target,
                                 child_orchestration_stack_vm_target,
                                 child_orchestration_stack_vm_target2], "_targeted_scope/orchestration_stack_refresh")
        end

        it "will refresh orchestration stack followed by LoadBalancer refresh" do
          refresh_with_cassette([parent_orchestration_stack_target], "_targeted_scope/orchestration_stack_refresh")
          ::Azure::Armrest::Configuration.clear_caches
          refresh_with_cassette([lb_target], "_targeted_scope/orchestration_stack_lb_refresh")
        end

        it "will refresh LoadBalancer created by stack" do
          refresh_with_cassette([lb_target], "_targeted_scope/lb_created_by_stack_refresh")
        end

        it "will refresh LoadBalancer" do
          refresh_with_cassette([lb_non_stack_target], "_targeted_scope/lb_refresh")
        end

        it "will refresh LoadBalancer with Vms refreshed before" do
          refresh_with_cassette(lbs_vms_targets, "_targeted_scope/lb_vms_refresh")
          refresh_with_cassette(lbs_targets, "_targeted_scope/lbs_refresh")
        end

        it "will refresh LoadBalancer with Vms" do
          refresh_with_cassette(lbs_targets + lbs_vms_targets, "_targeted_scope/lb_with_vms_refresh")
        end

        it "will refresh Template" do
          refresh_with_cassette([template_target], "_targeted_scope/template_refresh")
        end
      end
    end
  end

  def assert_all
    assert_table_counts
    assert_ems
    assert_specific_az
    assert_specific_cloud_network
    assert_specific_flavor
    assert_specific_disk
    assert_specific_security_group
    assert_specific_vm_powered_on
    assert_specific_vm_powered_off
    assert_specific_template
    assert_specific_orchestration_template
    assert_specific_orchestration_stack
    assert_specific_nic_and_ip
    assert_specific_load_balancers
    assert_specific_load_balancer_networking
    assert_specific_load_balancer_listeners
    assert_specific_load_balancer_health_checks
    assert_specific_vm_with_managed_disks
    assert_specific_managed_disk
    assert_specific_resource_group
  end
end
