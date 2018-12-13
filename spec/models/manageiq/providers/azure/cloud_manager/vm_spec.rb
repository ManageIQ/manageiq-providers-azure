describe ManageIQ::Providers::Azure::CloudManager::Vm do
  let(:ems) { FactoryBot.create(:ems_azure) }
  let(:host) { FactoryBot.create(:host, :ext_management_system => ems) }
  let(:vm) { FactoryBot.create(:vm_azure, :ext_management_system => ems, :host => host) }
  let(:power_state_on)  { "VM running" }
  let(:power_state_off) { "VM deallocated" }
  let(:power_state_suspended) { "VM stopping" }

  context "#is_available?" do
    context("with :start") do
      let(:state) { :start }
      include_examples "Vm operation is available when not powered on"
    end

    context("with :stop") do
      let(:state) { :stop }
      include_examples "Vm operation is available when powered on"
    end
  end

  context "reset" do
    it "does not support the reset operation" do
      expect(vm.supports_reset?).to be_falsy
      expect(vm.unsupported_reason(:reset)).to eql("Hard reboot not supported on Azure")
    end
  end
end
