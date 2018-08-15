require 'azure-armrest'
require_relative "azure_refresher_spec_common"

describe ManageIQ::Providers::Azure::CloudManager::Refresher do
  include AzureRefresherSpecCommon

  AzureRefresherSpecCommon::ALL_REFRESH_SETTINGS.each do |refresh_settings|
    context "with settings #{refresh_settings}" do
      before(:each) do
        @refresh_settings = refresh_settings

        stub_settings_merge(
          :ems_refresh => {
            :azure         => refresh_settings,
            :azure_network => refresh_settings,
          }
        )
      end

      before { define_shared_variables }

      after do
        ::Azure::Armrest::Configuration.clear_caches
      end

      it ".ems_type" do
        expect(described_class.ems_type).to eq(:azure)
      end

=begin
      context "marketplace images" do
        let(:urns) do
          [
            "Foo:Bar:Stuff:1.0",
            "Foo:Baz:Stuff:1.1",
            "Foo:Baz:MoreStuff:2.1",
            "Foo:Baz:MoreStuff:latest"
          ]
        end

        let(:settings) do
          {:ems_refresh => {:azure => {:get_market_images => true, :market_image_urns => urns}}}
        end

        it "does not collect marketplace images by default" do
          setup_ems_and_cassette(refresh_settings)
          expect(VmOrTemplate.where(:publicly_available => true).count).to eql(0)
        end

        it "collects only the marketplace images from the settings file if present" do
          stub_settings_merge(settings)
          setup_ems_and_cassette(refresh_settings)
          expect(VmOrTemplate.where(:publicly_available => true).count).to eql(4)
        end
      end
=end

=begin
      context "template deployments" do
        let(:template_deployment_service) { double }

        before do
          allow(template_deployment_service).to receive(:api_version=)
          allow(Azure::Armrest::TemplateDeploymentService).to receive(:new).and_return(template_deployment_service)
        end

        it "orchestration stack parsing handles an empty list of template deployments" do
          allow(template_deployment_service).to receive(:list).and_return([])
          setup_ems_and_cassette(refresh_settings)
          expect(OrchestrationStack.count).to eql(0)
        end
      end
=end

=begin
      context "proxy support" do
        let(:proxy) { URI::HTTP.build(:host => 'localhost', :port => 8080) }

        2.times do
          it "will perform a full refresh with a plain proxy enabled" do
            allow(VMDB::Util).to receive(:http_proxy_uri).and_return(proxy)
            setup_ems_and_cassette(refresh_settings)
            #expect(OrchestrationTemplate.count).to eql(26)
            #assert_specific_orchestration_template
          end
        end

        2.times do
          it "will perform a full refresh with an authenticating proxy enabled" do
            proxy.user = "foo"
            proxy.password = "xxx"

            allow(VMDB::Util).to receive(:http_proxy_uri).and_return(proxy)
            setup_ems_and_cassette(refresh_settings)
            #expect(OrchestrationTemplate.count).to eql(26)
            #assert_specific_orchestration_template
          end
        end
      end
=end

      it "will perform a full refresh" do
        2.times do # Run twice to verify that a second run with existing data does not change anything
          setup_ems_and_cassette(refresh_settings)

          #assert_table_counts
          assert_ems
          assert_specific_az
          #assert_specific_cloud_network
          assert_specific_flavor
          #assert_specific_disk
          assert_specific_security_group
          #assert_specific_vm_powered_on
          #assert_specific_vm_powered_off
          #assert_specific_template
          #assert_specific_orchestration_template
          #assert_specific_orchestration_stack
          #assert_specific_nic_and_ip
          #assert_specific_load_balancers
          #assert_specific_load_balancer_networking
          #assert_specific_load_balancer_listeners
          #assert_specific_load_balancer_health_checks
          #assert_specific_vm_with_managed_disks
          #assert_specific_managed_disk
          #assert_specific_resource_group
          #assert_specific_router
          #assert_specific_parent
        end
      end
    end
  end
end
