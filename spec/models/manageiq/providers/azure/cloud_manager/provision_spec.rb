describe ManageIQ::Providers::Azure::CloudManager::Provision do
  let(:provider)     { FactoryBot.create(:ems_azure_with_authentication) }
  let(:template)     { FactoryBot.create(:template_azure, :ext_management_system => provider) }
  let(:flavor)       { FactoryBot.create(:flavor_azure) }
  let(:vm)           { FactoryBot.create(:vm_azure, :ext_management_system => provider) }
  let(:sec_group)    { FactoryBot.create(:security_group_azure) }
  let(:subnet)       { FactoryBot.create(:cloud_subnet_azure) }
  let(:network_port) { FactoryBot.create(:network_port_azure) }
  let(:floating_ip)  { FactoryBot.create(:floating_ip_azure) }

  context "#create vm" do
    subscription_id = "01234567890"
    resource_group  = "test_resource_group"
    type            = "microsoft.resources"
    name            = "vm_1"
    nic_id          = "nic_id_1"

    before do
      subject.source = template
      allow(subject).to receive(:gather_storage_account_properties).and_return(%w("target_uri", "source_uri", "windows"))
      allow(subject).to receive(:create_nic).and_return(nic_id)
    end

    context "#validate_dest_name" do
      let(:vm) { FactoryBot.create(:vm_azure, :ext_management_system => provider) }

      it "with valid name" do
        allow(subject).to receive(:dest_name).and_return("new_vm_1")
        expect { subject.validate_dest_name }.to_not raise_error
      end

      it "with a blank name" do
        allow(subject).to receive(:dest_name).and_return("")
        expect { subject.validate_dest_name }
          .to raise_error(MiqException::MiqProvisionError, /Name cannot be blank/)
      end

      it "with a nil name" do
        allow(subject).to receive(:dest_name).and_return(nil)
        expect { subject.validate_dest_name }
          .to raise_error(MiqException::MiqProvisionError, /Name cannot be blank/)
      end

      it "with a duplicate name" do
        allow(subject).to receive(:dest_name).and_return(vm.name)
        expect { subject.validate_dest_name }
          .to raise_error(MiqException::MiqProvisionError, /already exists/)
      end
    end

    shared_examples 'prepare_for_clone_task' do |ems_ref|
      context "#prepare_for_clone_task" do
        let(:os) do
          Class.new do
            def product_name
              'Linux'
            end
          end.new
        end

        before do
          allow(subject).to receive(:instance_type).and_return(flavor)
          allow(subject).to receive(:dest_name).and_return(vm.name)
          allow(subject).to receive(:cloud_subnet).and_return(subnet)
          allow(template).to receive(:ems_ref).and_return(ems_ref)
          allow(template).to receive(:operating_system).and_return(os)
        end

        context "nic settings" do
          it "use existing floating_ip and assign to network profile" do
            allow(subject).to receive(:floating_ip).and_return(floating_ip)
            floating_ip.network_port = network_port
            expect(subject.prepare_for_clone_task[:properties][:networkProfile][:networkInterfaces][0][:id]).to eq(network_port.ems_ref)
          end

          it "without floating_ip create new nic and assign to network profile" do
            allow(subject).to receive(:floating_ip).and_return(nil)
            allow(subject).to receive(:options).and_return({:floating_ip_address => [-1, 'New']})
            expect(subject.prepare_for_clone_task[:properties][:networkProfile][:networkInterfaces][0][:id]).to eq(nic_id)
          end

          it "with floating_ip without network_port create new nic and assign to network profile" do
            allow(subject).to receive(:floating_ip).and_return(floating_ip)
            floating_ip.network_port = nil
            expect(subject.prepare_for_clone_task[:properties][:networkProfile][:networkInterfaces][0][:id]).to eq(nic_id)
          end
        end

        context "security group" do
          it "with security group" do
            allow(subject).to receive(:security_group).and_return(sec_group)
            expect(subject.build_nic_options("ip")[:properties][:networkSecurityGroup][:id]).to eq(sec_group.ems_ref)
          end

          it "without security group" do
            allow(subject).to receive(:security_group).and_return(nil)
            expect(subject.build_nic_options("ip")[:properties]).not_to have_key(:networkSecurityGroup)
          end
        end
      end
    end

    context "clone vm" do
      include_examples 'prepare_for_clone_task', 'abc/123'                # Unmanaged
      include_examples 'prepare_for_clone_task', '/subscriptions/abc/123' # Managed
    end

    it "#workflow" do
      user    = FactoryBot.create(:user)
      options = {:src_vm_id => [template.id, template.name]}
      vm_prov = FactoryBot.create(:miq_provision_azure,
                                   :userid       => user.userid,
                                   :source       => template,
                                   :request_type => 'template',
                                   :state        => 'pending',
                                   :status       => 'Ok',
                                   :options      => options)

      workflow_class = ManageIQ::Providers::Azure::CloudManager::ProvisionWorkflow
      allow_any_instance_of(workflow_class).to receive(:get_dialogs).and_return(:dialogs => {})

      expect(vm_prov.workflow.class).to eq workflow_class
      expect(vm_prov.workflow_class).to eq workflow_class
    end
  end
end
