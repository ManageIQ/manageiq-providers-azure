require 'azure-armrest'
require_relative "azure_refresher_spec_common"

describe ManageIQ::Providers::Azure::CloudManager::Refresher do
  include AzureRefresherSpecCommon

  [
    {
      :enabled_deployments_caching => true,
      :get_private_images          => true,
      :inventory_object_refresh    => true,
      :inventory_collections       => {
        :saver_strategy => :default,
      },
    }, {
      :enabled_deployments_caching => false,
      :get_private_images          => true,
      :inventory_object_refresh    => true,
      :inventory_collections       => {
        :saver_strategy => :default,
      },
    }
  ].each do |refresh_settings|
    context "with settings #{refresh_settings}" do
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

      it "will refresh orchestration stack" do
        @refresh_settings = refresh_settings.merge(:allow_targeted_refresh => true)

        stub_settings_merge(
          :ems_refresh => {
            :azure         => @refresh_settings,
            :azure_network => @refresh_settings,
          }
        )

        2.times do # Run twice to verify that a second run with existing data does not change anything
          refresh_with_cassette(
            [parent_orchestration_stack_target],
            "_targeted/targeted_api_collection_threshold_500/orchestration_stack_refresh"
          )

          assert_stack_and_vm_targeted_refresh
        end
      end

      it "will perform a full refresh" do
        @refresh_settings = refresh_settings
        2.times do # Run twice to verify that a second run with existing data does not change anything
          setup_ems_and_cassette(refresh_settings)

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
    end
  end
end
