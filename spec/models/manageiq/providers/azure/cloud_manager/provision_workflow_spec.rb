describe ManageIQ::Providers::Azure::CloudManager::ProvisionWorkflow do
  include Spec::Support::WorkflowHelper

  let(:admin)    { FactoryBot.create(:user_with_group) }
  let(:ems)      { FactoryBot.create(:ems_azure) }
  let(:template) { FactoryBot.create(:template_azure, :name => "template", :ext_management_system => ems) }
  let(:workflow) do
    stub_dialog
    allow_any_instance_of(User).to receive(:get_timezone).and_return(Time.zone)
    allow_any_instance_of(ManageIQ::Providers::CloudManager::ProvisionWorkflow).to receive(:update_field_visibility)

    wf = described_class.new({:src_vm_id => template.id}, admin.userid)
    wf.instance_variable_set("@ems_xml_nodes", {})
    wf
  end

  it "pass platform attributes to automate" do
    stub_dialog
    assert_automate_dialog_lookup(admin, 'cloud', 'azure')
    described_class.new({}, admin.userid)
  end

  context "without applied tags" do
    context "Instance Type (Flavor)" do
      it "#get_targets_for_ems" do
        flavor = FactoryBot.create(:flavor, :name => "Standard_A0", :supports_32_bit => false,
                                    :supports_64_bit => true)
        ems.flavors << flavor
        expect(workflow.allowed_instance_types.length).to eq(1)
      end
    end

    context "security_groups" do
      context "non cloud network" do
        it "#get_targets_for_ems" do
          sg = FactoryBot.create(:security_group, :ext_management_system => ems.network_manager)
          ems.security_groups << sg
          filtered = workflow.send(:get_targets_for_ems, ems, :cloud_filter, SecurityGroup,
                                   'security_groups.non_cloud_network')
          expect(filtered.size).to eq(1)
          expect(filtered.first.name).to eq(sg.name)
        end
      end

      context "cloud network" do
        it "#get_targets_for_ems" do
          cn1 = FactoryBot.create(:cloud_network, :ext_management_system => ems.network_manager)
          sg_cn = FactoryBot.create(:security_group, :ext_management_system => ems.network_manager, :cloud_network => cn1)
          ems.security_groups << sg_cn
          filtered = workflow.send(:get_targets_for_ems, ems, :cloud_filter, SecurityGroup, 'security_groups')
          expect(filtered.size).to eq(1)
          expect(filtered.first.name).to eq(sg_cn.name)
        end
      end
    end

    context "floating ips" do
      before do
        FactoryBot.create(:network_port_azure, :id => 1, :device_id => nil)
        ems.floating_ips << FactoryBot.create(
          :floating_ip_azure,
          :ext_management_system => ems.network_manager,
          :network_port_id       => 1
        )

        FactoryBot.create(:network_port_azure, :id => 2, :device_id => 1)
        ems.floating_ips << FactoryBot.create(
          :floating_ip_azure,
          :ext_management_system => ems.network_manager,
          :network_port_id       => 2
        )

        ems.floating_ips << FactoryBot.create(
          :floating_ip_azure,
          :ext_management_system => ems.network_manager,
          :network_port_id       => nil
        )
      end

      it "allowed_floating_ips" do
        expect(workflow.allowed_floating_ip_addresses.length).to eq(3)
        expect(workflow.allowed_floating_ip_addresses[-1]).to eq('New')
      end
    end
  end

  context "with applied tags" do
    before do
      FactoryBot.create(:classification_cost_center_with_tags)
      admin.current_group.entitlement = Entitlement.create!
      admin.current_group.entitlement.set_managed_filters([['/managed/cc/001']])
      admin.current_group.save!
      ems.flavors << FactoryBot.create(:flavor, :name => "Standard_A0", :supports_32_bit => false,
                                        :supports_64_bit => true)
      ems.flavors << FactoryBot.create(:flavor, :name => "Standard_A1", :supports_32_bit => false,
                                        :supports_64_bit => true)
      tagged_flavor = ems.flavors.first
      Classification.classify(tagged_flavor, 'cc', '001')

      2.times { FactoryBot.create(:security_group, :ext_management_system => ems.network_manager) }
      tagged_sec = ems.security_groups.first
      Classification.classify(tagged_sec, 'cc', '001')
    end

    context "security groups" do
      it "#get_targets_for_ems" do
        expect(ems.security_groups.size).to eq(2)
        expect(ems.security_groups.first.tags.size).to eq(1)
        expect(ems.security_groups.last.tags.size).to eq(0)

        expect(workflow.send(:get_targets_for_ems,
                             ems,
                             :cloud_filter,
                             SecurityGroup,
                             'security_groups').size)
          .to eq(1)
      end
    end

    context "instance types (Flavor)" do
      it "#get_targets_for_ems" do
        expect(ems.flavors.size).to eq(2)
        expect(ems.flavors.first.tags.size).to eq(1)
        expect(ems.flavors.last.tags.size).to eq(0)
        expect(workflow.allowed_instance_types.length).to eq(2)
      end
    end
  end

  context "when a template object is returned from the provider" do
    context "with empty relationships" do
      it "#allowed_instance_types" do
        expect(workflow.allowed_instance_types).to eq({})
      end

      it "#allowed_resource_groups" do
        expect(workflow.allowed_resource_groups).to eq({})
      end
    end

    context "with valid relationships" do
      before do
        ems.flavors << FactoryBot.create(:flavor, :name => "Standard_A0", :supports_32_bit => false,
                                          :supports_64_bit => true)
        ems.flavors << FactoryBot.create(:flavor, :name => "Standard_A1", :supports_32_bit => false,
                                          :supports_64_bit => true)
        ems.resource_groups << FactoryBot.create(:azure_resource_group)
        ems.resource_groups << FactoryBot.create(:azure_resource_group)
      end

      it "#allowed_instance_types" do
        expect(workflow.allowed_instance_types.length).to eq(2)
      end

      it "allowed_resource_groups" do
        expect(workflow.allowed_resource_groups.length).to eq(2)
      end
    end
  end

  context "with VPC relationships" do
    before do
      @az1 = FactoryBot.create(:availability_zone, :ext_management_system => ems)
      @cn1 = FactoryBot.create(:cloud_network, :ext_management_system => ems.network_manager)
      @cn2 = FactoryBot.create(:cloud_network, :ext_management_system => ems.network_manager)
      FactoryBot.create(:cloud_subnet, :cloud_network => @cn1, :availability_zone => @az1)
      FactoryBot.create(:cloud_subnet, :cloud_network => @cn1)
    end

    context "#allowed_cloud_subnets" do
      it "without a cloud_network" do
        expect(workflow.allowed_cloud_subnets.length).to be_zero
      end

      it "with a cloud_network" do
        workflow.values[:cloud_network] = [@cn1.id, @cn1.name]
        expect(workflow.allowed_cloud_subnets.length).to eq(2)
      end
    end

    context "#allowed_cloud_networks" do
      it "#allowed_cloud_networks with zone" do
        workflow.values[:placement_availability_zone] = [@az1.id, @az1.name]
        cns = workflow.allowed_cloud_networks
        expect(cns.keys).to match_array [@cn1.id]
      end

      it "#allowed_cloud_networks without availability zone returns everything" do
        FactoryBot.create(:cloud_subnet, :cloud_network => @cn2)
        cns = workflow.allowed_cloud_networks
        expect(cns.keys).to match_array [@cn1.id, @cn2.id]
      end

      it "#allowed_cloud_networks without subnet" do
        cns = workflow.allowed_cloud_networks
        expect(cns.keys).to match_array [@cn1.id]
      end
    end
  end

  context "#display_name_for_name_description" do
    let(:flavor) { FactoryBot.create(:flavor_azure, :name => "test_flavor") }

    it "with name only" do
      expect(workflow.display_name_for_name_description(flavor)).to eq("test_flavor")
    end

    it "with name and description" do
      flavor.description = "Small"
      expect(workflow.display_name_for_name_description(flavor)).to eq("test_flavor: Small")
    end
  end

  context "#supports_sysprep?" do
    it "returns the expected boolean value" do
      expect(workflow.supports_sysprep?).to eql(true)
    end
  end

  describe "#make_request" do
    let(:alt_user) { FactoryBot.create(:user_with_group) }
    it "creates and update a request" do
      stub_dialog(:get_pre_dialogs)
      stub_dialog(:get_dialogs)

      # if running_pre_dialog is set, it will run 'continue_request'
      workflow = described_class.new(values = {:running_pre_dialog => false}, admin)

      expect(AuditEvent).to receive(:success).with(
        :event        => "vm_provision_request_created",
        :target_class => "Vm",
        :userid       => admin.userid,
        :message      => "VM Provisioning requested by <#{admin.userid}> for Vm:#{template.id}"
      )

      # creates a request
      stub_get_next_vm_name

      # the dialogs populate this
      values.merge!(:src_vm_id => template.id, :vm_tags => [])

      request = workflow.make_request(nil, values)

      expect(request).to be_valid
      expect(request).to be_a_kind_of(MiqProvisionRequest)
      expect(request.request_type).to eq("template")
      expect(request.description).to eq("Provision from [#{template.name}] to [New VM]")
      expect(request.requester).to eq(admin)
      expect(request.userid).to eq(admin.userid)
      expect(request.requester_name).to eq(admin.name)

      # updates a request

      stub_get_next_vm_name

      workflow = described_class.new(values, alt_user)

      expect(AuditEvent).to receive(:success).with(
        :event        => "vm_provision_request_updated",
        :target_class => "Vm",
        :userid       => alt_user.userid,
        :message      => "VM Provisioning request updated by <#{alt_user.userid}> for Vm:#{template.id}"
      )
      workflow.make_request(request, values)
    end
  end
end
