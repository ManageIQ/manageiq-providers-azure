require 'azure-armrest'
require_relative "azure_refresher_spec_common"

describe ManageIQ::Providers::Azure::CloudManager::Refresher do
  include AzureRefresherSpecCommon

  AzureRefresherSpecCommon::ALL_GRAPH_REFRESH_SETTINGS.each do |refresh_settings|
    context "with settings #{refresh_settings}" do
      AzureRefresherSpecCommon::GRAPH_REFRESH_ADDITIONAL_SETTINGS.each do |additional_settings|
        context "with additional settings #{additional_settings}" do
          before(:each) do
            @refresh_settings = refresh_settings.merge(:allow_targeted_refresh => true)
            @refresh_settings.merge!(additional_settings)

            @sub_path = "targeted_api_collection_threshold_#{additional_settings[:targeted_api_collection_threshold]}/"

            stub_settings_merge(
              :ems_refresh => {
                :azure         => @refresh_settings,
                :azure_network => @refresh_settings,
              }
            )
          end

          before do
            define_shared_variables
            @mismatch_ip = '23.96.82.94'
            @vm_resource_group = 'miq-vms-eastus'
            @vm_centos = 'miq-vm-centos1-eastus'
          end

          after do
            ::Azure::Armrest::Configuration.clear_caches
          end

          it ".ems_type" do
            expect(described_class.ems_type).to eq(:azure)
          end

          it "will refresh powered on VM" do
            2.times do # Run twice to verify that a second run with existing data does not change anything
              refresh_with_cassette([vm_powered_on_target], vcr_suffix("powered_on_vm_refresh"))

              assert_specific_az
              assert_specific_cloud_network
              assert_specific_flavor
              assert_specific_disk
              assert_specific_security_group
              assert_specific_vm_powered_on

              assert_counts(
                :availability_zone     => 1,
                :cloud_network         => 1,
                :cloud_subnet          => 1,
                :disk                  => 1,
                :ext_management_system => 2,
                :flavor                => 1,
                :floating_ip           => 1,
                :hardware              => 1,
                :network               => 2,
                :network_port          => 1,
                :operating_system      => 1,
                :resource_group        => 1,
                :security_group        => 1,
                :vm                    => 1,
                :vm_or_template        => 1
              )
            end
          end

          it "will refresh powered off VM" do
            2.times do # Run twice to verify that a second run with existing data does not change anything
              refresh_with_cassette([vm_powered_off_target], vcr_suffix("powered_off_vm_refresh"))

              assert_specific_az
              assert_specific_flavor
              assert_specific_vm_powered_off

              assert_counts(
                :availability_zone     => 1,
                :cloud_network         => 1,
                :cloud_subnet          => 1,
                :disk                  => 1,
                :ext_management_system => 2,
                :flavor                => 1,
                :floating_ip           => 1,
                :hardware              => 1,
                :network               => 2,
                :network_port          => 1,
                :operating_system      => 1,
                :resource_group        => 1,
                :security_group        => 0,
                :vm                    => 1,
                :vm_or_template        => 1
              )
            end
          end

          it "will reconnect powered off VM" do
            existing_ref = "#{@ems.subscription}/#{@vm_resource_group}/microsoft.compute/virtualmachines/#{@vm_centos}"
            vm_oldest    = FactoryBot.create(:vm_azure, :ems_ref => existing_ref, :uid_ems => existing_ref)
            FactoryBot.create(:vm_azure, :ems_ref => existing_ref, :uid_ems => existing_ref)

            2.times do # Run twice to verify that a second run with existing data does not change anything
              refresh_with_cassette([vm_powered_off_target], vcr_suffix("powered_off_vm_refresh"))

              assert_specific_az
              assert_specific_flavor
              assert_specific_vm_powered_off

              expect(Vm.count).to eq(2)
              expect(@ems.vms.count).to eq(1)
              # We will reconnect the oldest one
              expect(@ems.vms.first.id).to eq(vm_oldest.id)
            end
          end

          it "will refresh VM with managed disk" do
            2.times do # Run twice to verify that a second run with existing data does not change anything
              refresh_with_cassette([vm_with_managed_disk_target], vcr_suffix("vm_with_managed_disk_refresh"))

              assert_specific_az
              assert_specific_flavor(true)
              assert_specific_vm_with_managed_disks
              assert_specific_managed_disk

              assert_counts(
                :availability_zone     => 1,
                :cloud_network         => 1,
                :cloud_subnet          => 1,
                :disk                  => 2,
                :ext_management_system => 2,
                :flavor                => 1,
                :floating_ip           => 1,
                :hardware              => 1,
                :network               => 2,
                :network_port          => 1,
                :operating_system      => 1,
                :resource_group        => 1,
                :security_group        => 0,
                :vm                    => 1,
                :vm_or_template        => 1
              )
            end
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

            2.times do # Run twice to verify that a second run with existing data does not change anything
              refresh_with_cassette(targets, vcr_suffix("multiple_targets_refresh"))

              assert_specific_az
              assert_specific_cloud_network
              assert_specific_flavor

              assert_specific_disk
              assert_specific_security_group
              assert_specific_vm_powered_on

              assert_specific_vm_powered_off

              assert_specific_vm_with_managed_disks
              assert_specific_managed_disk

              assert_counts(
                :ext_management_system             => 2,
                :flavor                            => 3,
                :availability_zone                 => 1,
                :vm_or_template                    => 3,
                :vm                                => 3,
                :disk                              => 4,
                :hardware                          => 3,
                :network                           => 6,
                :operating_system                  => 3,
                :security_group                    => 1,
                :network_port                      => 4,
                :cloud_network                     => 1,
                :floating_ip                       => 4,
                :cloud_subnet                      => 1,
                :resource_group                    => 2,
                :load_balancer                     => 1,
                :load_balancer_pool                => 1,
                :load_balancer_pool_member         => 2,
                :load_balancer_pool_member_pool    => 2,
                :load_balancer_listener            => 1,
                :load_balancer_listener_pool       => 1,
                :load_balancer_health_check        => 2,
                :load_balancer_health_check_member => 2
              )
            end
          end

          it "will refresh cloud network" do
            2.times do # Run twice to verify that a second run with existing data does not change anything
              refresh_with_cassette([cloud_network_target], vcr_suffix("cloud_network_refresh"))
              assert_counts(
                :cloud_network         => 1,
                :cloud_subnet          => 1,
                :ext_management_system => 2
              )
            end
          end

          it "will refresh resource group target" do
            2.times do # Run twice to verify that a second run with existing data does not change anything
              refresh_with_cassette([resource_group_target], vcr_suffix("resource_group_refresh"))
              assert_counts(
                :resource_group        => 1,
                :ext_management_system => 2
              )
            end
          end

          it "will refresh security group target" do
            2.times do # Run twice to verify that a second run with existing data does not change anything
              refresh_with_cassette([security_group_target], vcr_suffix("security_group_refresh"))
              assert_counts(
                :security_group        => 1,
                :ext_management_system => 2
              )
            end
          end

          it "will refresh network_port target" do
            2.times do # Run twice to verify that a second run with existing data does not change anything
              refresh_with_cassette([network_port_target], vcr_suffix("network_port_refresh"))
              assert_counts(
                :cloud_network         => 1,
                :cloud_subnet          => 1,
                :ext_management_system => 2,
                :floating_ip           => 1,
                :network_port          => 1,
                :security_group        => 1,
              )
            end
          end

          it "will refresh orchestration stack" do
            2.times do # Run twice to verify that a second run with existing data does not change anything
              refresh_with_cassette([parent_orchestration_stack_target], vcr_suffix("orchestration_stack_refresh"))

              assert_stack_and_vm_targeted_refresh
            end
          end

          # it "will refresh orchestration stack followed by Vm refresh" do
          #   2.times do # Run twice to verify that a second run with existing data does not change anything
          #     refresh_with_cassette([parent_orchestration_stack_target], vcr_suffix("orchestration_stack_refresh"))
          #
          #     assert_stack_and_vm_targeted_refresh
          #
          #     refresh_with_cassette([child_orchestration_stack_vm_target], vcr_suffix("orchestration_stack_vm_refresh"))
          #     assert_stack_and_vm_targeted_refresh
          #   end
          # end

          # it "will refresh orchestration stack with vms" do
          #   2.times do # Run twice to verify that a second run with existing data does not change anything
          #     refresh_with_cassette([parent_orchestration_stack_target,
          #                            child_orchestration_stack_vm_target,
          #                            child_orchestration_stack_vm_target2], vcr_suffix("orchestration_stack_refresh"))
          #
          #     assert_stack_and_vm_targeted_refresh
          #   end
          # end

          # it "will refresh orchestration stack followed by LoadBalancer refresh" do
          #   2.times do # Run twice to verify that a second run with existing data does not change anything
          #     refresh_with_cassette([parent_orchestration_stack_target], vcr_suffix("orchestration_stack_refresh"))
          #
          #     assert_stack_and_vm_targeted_refresh
          #
          #     refresh_with_cassette([lb_target], vcr_suffix("orchestration_stack_lb_refresh"))
          #     assert_stack_and_vm_targeted_refresh
          #   end
          # end

          it "will refresh LoadBalancer created by stack" do
            2.times do # Run twice to verify that a second run with existing data does not change anything
              refresh_with_cassette([lb_target], vcr_suffix("lb_created_by_stack_refresh"))

              assert_counts(
                :ext_management_system             => 2,
                :floating_ip                       => 1,
                :load_balancer                     => 1,
                :load_balancer_health_check        => 2,
                :load_balancer_health_check_member => 2,
                :load_balancer_listener            => 1,
                :load_balancer_listener_pool       => 1,
                :load_balancer_pool                => 1,
                :load_balancer_pool_member         => 2,
                :load_balancer_pool_member_pool    => 2,
                :network_port                      => 1,
              )
            end
          end

          it "will refresh LoadBalancer" do
            2.times do # Run twice to verify that a second run with existing data does not change anything
              refresh_with_cassette([lb_non_stack_target], vcr_suffix("lb_refresh"))

              assert_counts(
                :ext_management_system             => 2,
                :floating_ip                       => 1,
                :load_balancer                     => 1,
                :load_balancer_health_check        => 2,
                :load_balancer_health_check_member => 2,
                :load_balancer_listener            => 1,
                :load_balancer_listener_pool       => 1,
                :load_balancer_pool                => 1,
                :load_balancer_pool_member         => 2,
                :load_balancer_pool_member_pool    => 2,
                :network_port                      => 1
              )
            end
          end

          it "will refresh LoadBalancer with Vms refreshed before" do
            # Refresh Vms first
            2.times do # Run twice to verify that a second run with existing data does not change anything
              # Refresh Vms
              refresh_with_cassette(lbs_vms_targets, vcr_suffix("lb_vms_refresh"))

              assert_counts(
                :availability_zone     => 1,
                :cloud_network         => 1,
                :cloud_subnet          => 1,
                :disk                  => 2,
                :ext_management_system => 2,
                :flavor                => 1,
                :floating_ip           => 0,
                :hardware              => 2,
                :network               => 2,
                :network_port          => 2,
                :operating_system      => 2,
                :resource_group        => 1,
                :security_group        => 1,
                :vm                    => 2,
                :vm_or_template        => 2
              )
            end

            # Refresh LBs, those have to connect to the Vms
            2.times do # Run twice to verify that a second run with existing data does not change anything
              refresh_with_cassette(lbs_targets, vcr_suffix("lbs_refresh"))

              assert_lbs_with_vms
            end
          end

          it "will refresh LoadBalancer with Vms" do
            2.times do # Run twice to verify that a second run with existing data does not change anything
              refresh_with_cassette(lbs_targets + lbs_vms_targets, vcr_suffix("lb_with_vms_refresh"))

              assert_lbs_with_vms
            end
          end

          it "will refresh Template" do
            2.times do # Run twice to verify that a second run with existing data does not change anything
              refresh_with_cassette([template_target], vcr_suffix("template_refresh"))

              # assert_specific_template
            end
          end

          def vcr_suffix(suffix)
            "_targeted/#{@sub_path}#{suffix}"
          end
        end
      end
    end
  end
end
