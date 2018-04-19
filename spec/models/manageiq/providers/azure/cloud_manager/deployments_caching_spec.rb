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
      before { define_shared_variables }

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
