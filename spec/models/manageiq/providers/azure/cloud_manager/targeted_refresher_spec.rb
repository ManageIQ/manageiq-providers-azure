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
        @mismatch_ip       = '52.168.33.118'  # This will change if you had to restart the 'miqmismatch1' VM.
        @managed_os_disk   = "miqazure-linux-managed_OsDisk_1_7b2bdf790a7d4379ace2846d307730cd"
        @managed_data_disk = "miqazure-linux-managed-data-disk"
        @template          = nil
        @avail_zone        = nil

        @resource_group_managed_vm = "miq-azure-test4"
      end

      after do
        ::Azure::Armrest::Configuration.clear_caches
      end

      it ".ems_type" do
        expect(described_class.ems_type).to eq(:azure)
      end

      it "will refresh powered on VM" do
        vm_resource_id = "#{@ems.subscription}\\#{@resource_group}\\microsoft.compute/virtualmachines\\#{@device_name}"

        vm_target = ManagerRefresh::Target.new(:manager     => @ems,
                                               :association => :vms,
                                               :manager_ref => {:ems_ref => vm_resource_id})

        2.times do # Run twice to verify that a second run with existing data does not change anything
          refresh_with_cassette([vm_target], "_targeted/powered_on_vm_refresh")

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
            :miq_queue             => 2,
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
        vm_resource_id = "#{@ems.subscription}\\#{@resource_group}\\microsoft.compute/virtualmachines\\#{@vm_powered_off}"

        vm_target = ManagerRefresh::Target.new(:manager     => @ems,
                                               :association => :vms,
                                               :manager_ref => {:ems_ref => vm_resource_id})

        2.times do # Run twice to verify that a second run with existing data does not change anything
          refresh_with_cassette([vm_target], "_targeted/powered_off_vm_refresh")

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
            :miq_queue             => 2,
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

      it "will refresh VM with managed disk" do
        vm_resource_id = "#{@ems.subscription}\\#{@resource_group_managed_vm}\\microsoft.compute/virtualmachines\\#{@managed_vm}"

        vm_target = ManagerRefresh::Target.new(:manager     => @ems,
                                               :association => :vms,
                                               :manager_ref => {:ems_ref => vm_resource_id})

        2.times do # Run twice to verify that a second run with existing data does not change anything
          refresh_with_cassette([vm_target], "_targeted/vm_with_managed_disk_refresh")

          assert_specific_az
          assert_specific_flavor
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
            :miq_queue             => 2,
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

      it "will refresh orchestration stack" do
        stack_resource_id = "/subscriptions/#{@ems.subscription}/resourceGroups/miq-azure-test1/providers/Microsoft.Resources/deployments/spec-deployment-dont-delete"

        stack_target = ManagerRefresh::Target.new(:manager     => @ems,
                                                  :association => :orchestration_stacks,
                                                  :manager_ref => {:ems_ref => stack_resource_id})

        2.times do # Run twice to verify that a second run with existing data does not change anything
          refresh_with_cassette([stack_target], "_targeted/orchestration_stack_refresh")

          assert_stack_and_vm_targeted_refresh
        end
      end

      it "will refresh orchestration stack followed by Vm refresh" do
        stack_resource_id = "/subscriptions/#{@ems.subscription}/resourceGroups/miq-azure-test1/providers/Microsoft.Resources/deployments/spec-deployment-dont-delete"

        stack_target = ManagerRefresh::Target.new(:manager     => @ems,
                                                  :association => :orchestration_stacks,
                                                  :manager_ref => {:ems_ref => stack_resource_id})

        vm_resource_id = "#{@ems.subscription}\\miq-azure-test1\\microsoft.compute/virtualmachines\\spec0deply1vm0"
        vm_target = ManagerRefresh::Target.new(:manager     => @ems,
                                               :association => :vms,
                                               :manager_ref => {:ems_ref => vm_resource_id})

        2.times do # Run twice to verify that a second run with existing data does not change anything
          refresh_with_cassette([stack_target], "_targeted/orchestration_stack_refresh")

          assert_stack_and_vm_targeted_refresh

          refresh_with_cassette([vm_target], "_targeted/orchestration_stack_vm_refresh")
          assert_stack_and_vm_targeted_refresh
        end
      end

      it "will refresh orchestration stack with vms" do
        stack_resource_id = "/subscriptions/#{@ems.subscription}/resourceGroups/miq-azure-test1/providers/Microsoft.Resources/deployments/spec-deployment-dont-delete"

        stack_target = ManagerRefresh::Target.new(:manager     => @ems,
                                                  :association => :orchestration_stacks,
                                                  :manager_ref => {:ems_ref => stack_resource_id})

        vm_resource_id1 = "#{@ems.subscription}\\miq-azure-test1\\microsoft.compute/virtualmachines\\spec0deply1vm0"
        vm_target1      = ManagerRefresh::Target.new(:manager     => @ems,
                                                     :association => :vms,
                                                     :manager_ref => {:ems_ref => vm_resource_id1})

        vm_resource_id2 = "#{@ems.subscription}\\miq-azure-test1\\microsoft.compute/virtualmachines\\spec0deply1vm1"
        vm_target2      = ManagerRefresh::Target.new(:manager     => @ems,
                                                     :association => :vms,
                                                     :manager_ref => {:ems_ref => vm_resource_id2})

        2.times do # Run twice to verify that a second run with existing data does not change anything
          refresh_with_cassette([stack_target, vm_target1, vm_target2], "_targeted/orchestration_stack_refresh")

          assert_stack_and_vm_targeted_refresh
        end
      end

      it "will refresh orchestration stack followed by LoadBalancer refresh" do
        stack_resource_id = "/subscriptions/#{@ems.subscription}/resourceGroups/miq-azure-test1/providers/Microsoft.Resources/deployments/spec-deployment-dont-delete"

        stack_target = ManagerRefresh::Target.new(:manager     => @ems,
                                                  :association => :orchestration_stacks,
                                                  :manager_ref => {:ems_ref => stack_resource_id})

        lb_resource_id = "/subscriptions/#{@ems.subscription}/resourceGroups/miq-azure-test1/providers/Microsoft.Network/loadBalancers/spec0deply1lb"
        lb_target = ManagerRefresh::Target.new(:manager     => @ems,
                                               :association => :load_balancers,
                                               :manager_ref => {:ems_ref => lb_resource_id})

        2.times do # Run twice to verify that a second run with existing data does not change anything
          refresh_with_cassette([stack_target], "_targeted/orchestration_stack_refresh")

          assert_stack_and_vm_targeted_refresh

          refresh_with_cassette([lb_target], "_targeted/orchestration_stack_lb_refresh")
          assert_stack_and_vm_targeted_refresh
        end
      end

      it "will refresh LoadBalancer created by stack" do
        lb_resource_id = "/subscriptions/#{@ems.subscription}/resourceGroups/miq-azure-test1/providers/Microsoft.Network/loadBalancers/spec0deply1lb"
        lb_target = ManagerRefresh::Target.new(:manager     => @ems,
                                               :association => :load_balancers,
                                               :manager_ref => {:ems_ref => lb_resource_id})

        2.times do # Run twice to verify that a second run with existing data does not change anything
          refresh_with_cassette([lb_target], "_targeted/lb_created_by_stack_refresh")

          assert_counts(
            :ext_management_system => 2,
            :floating_ip           => 1,
            :load_balancer         => 1,
            :miq_queue             => 1,
            :network_port          => 1,
          )
        end
      end

      it "will refresh LoadBalancer" do
        lb_resource_id = "/subscriptions/#{@ems.subscription}/"\
                          "resourceGroups/miq-azure-test1/providers/Microsoft.Network/loadBalancers/rspec-lb1"
        lb_target = ManagerRefresh::Target.new(:manager     => @ems,
                                               :association => :load_balancers,
                                               :manager_ref => {:ems_ref => lb_resource_id})

        2.times do # Run twice to verify that a second run with existing data does not change anything
          refresh_with_cassette([lb_target], "_targeted/lb_refresh")

          assert_counts(
            :ext_management_system => 2,
            :floating_ip           => 1,
            :load_balancer         => 1,
            :miq_queue             => 1,
            :network_port          => 1
          )
        end
      end

      it "will refresh LoadBalancer with Vms refreshed before" do
        # Refresh Vms first
        2.times do # Run twice to verify that a second run with existing data does not change anything
          # Refresh Vms
          refresh_with_cassette(lbs_vms_targets, "_targeted/lb_vms_refresh")

          assert_counts(
            :availability_zone     => 1,
            :cloud_network         => 1,
            :cloud_subnet          => 1,
            :disk                  => 2,
            :ext_management_system => 2,
            :flavor                => 2,
            :floating_ip           => 2,
            :hardware              => 2,
            :miq_queue             => 3,
            :network               => 4,
            :network_port          => 2,
            :operating_system      => 2,
            :resource_group        => 1,
            :security_group        => 2,
            :vm                    => 2,
            :vm_or_template        => 2
          )
        end

        # Refresh LBs, those have to connect to the Vms
        2.times do # Run twice to verify that a second run with existing data does not change anything
          refresh_with_cassette(lbs_targets, "_targeted/lbs_refresh")

          assert_lbs_with_vms
        end
      end

      it "will refresh LoadBalancer with Vms" do
        2.times do # Run twice to verify that a second run with existing data does not change anything
          refresh_with_cassette(lbs_targets + lbs_vms_targets, "_targeted/lb_with_vms_refresh")

          assert_lbs_with_vms
        end
      end

      it "will refresh Template" do
        template_resource_id = "https://miqazuretest14047.blob.core.windows.net/system/"\
                               "Microsoft.Compute/Images/miq-test-container/"\
                               "test-win2k12-img-osDisk.e17a95b0-f4fb-4196-93c5-0c8be7d5c536.vhd"

        template_target = ManagerRefresh::Target.new(:manager     => @ems,
                                                     :association => :miq_templates,
                                                     :manager_ref => {:ems_ref => template_resource_id})

        2.times do # Run twice to verify that a second run with existing data does not change anything
          refresh_with_cassette([template_target], "_targeted/template_refresh")

          assert_specific_template
        end
      end

      def lbs_targets
        lb_resource_id1 = "/subscriptions/#{@ems.subscription}/"\
                          "resourceGroups/miq-azure-test1/providers/Microsoft.Network/loadBalancers/rspec-lb1"
        lb_target1      = ManagerRefresh::Target.new(:manager     => @ems,
                                                     :association => :load_balancers,
                                                     :manager_ref => {:ems_ref => lb_resource_id1})

        lb_resource_id2 = "/subscriptions/#{@ems.subscription}/"\
                          "resourceGroups/miq-azure-test1/providers/Microsoft.Network/loadBalancers/rspec-lb2"
        lb_target2      = ManagerRefresh::Target.new(:manager     => @ems,
                                                     :association => :load_balancers,
                                                     :manager_ref => {:ems_ref => lb_resource_id2})
        [lb_target1, lb_target2]
      end

      def lbs_vms_targets
        vm_resource_id1 = "#{@ems.subscription}\\miq-azure-test1\\microsoft.compute/virtualmachines\\rspec-lb-a"
        vm_target1      = ManagerRefresh::Target.new(:manager     => @ems,
                                                     :association => :vms,
                                                     :manager_ref => {:ems_ref => vm_resource_id1})

        vm_resource_id2 = "#{@ems.subscription}\\miq-azure-test1\\microsoft.compute/virtualmachines\\rspec-lb-b"
        vm_target2      = ManagerRefresh::Target.new(:manager     => @ems,
                                                     :association => :vms,
                                                     :manager_ref => {:ems_ref => vm_resource_id2})
        [vm_target1, vm_target2]
      end

      def assert_lbs_with_vms
        assert_specific_load_balancers
        assert_specific_load_balancer_networking
        assert_specific_load_balancer_listeners
        assert_specific_load_balancer_health_checks

        assert_counts(
          :availability_zone     => 1,
          :cloud_network         => 1,
          :cloud_subnet          => 1,
          :disk                  => 2,
          :ext_management_system => 2,
          :flavor                => 2,
          :floating_ip           => 4,
          :hardware              => 2,
          :load_balancer         => 2,
          :miq_queue             => 3,
          :network               => 4,
          :network_port          => 4,
          :operating_system      => 2,
          :resource_group        => 1,
          :security_group        => 2,
          :vm                    => 2,
          :vm_or_template        => 2
        )
      end

      def assert_stack_and_vm_targeted_refresh
        assert_specific_orchestration_template
        assert_specific_orchestration_stack

        assert_counts(
          :availability_zone             => 1,
          :cloud_network                 => 1,
          :cloud_subnet                  => 1,
          :disk                          => 2,
          :ext_management_system         => 2,
          :flavor                        => 1,
          :floating_ip                   => 1,
          :hardware                      => 2,
          :load_balancer                 => 1,
          :miq_queue                     => 3,
          :network                       => 2,
          :network_port                  => 3,
          :operating_system              => 2,
          :orchestration_stack           => 2,
          :orchestration_stack_output    => 1,
          :orchestration_stack_parameter => 29,
          :orchestration_stack_resource  => 10,
          :orchestration_template        => 2,
          :resource_group                => 1,
          :vm                            => 2,
          :vm_or_template                => 2
        )
      end
    end
  end
end
