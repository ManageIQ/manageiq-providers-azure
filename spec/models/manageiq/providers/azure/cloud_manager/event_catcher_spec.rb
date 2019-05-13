describe ManageIQ::Providers::Azure::CloudManager::EventCatcher do
  context "valid ems" do
    let(:unsupported_reason) { "Timeline events not supported for this region" }

    before do
      server = EvmSpecHelper.local_miq_server
      @ems = FactoryGirl.create(:ems_azure, :with_authentication, :zone => server.zone)
    end

    it "returns a valid ems for zone if timeline events are supported" do
      expect_any_instance_of(@ems.class).to receive(:supports_timeline?).and_return(true)
      expect($log).not_to receive(:info).with(/#{unsupported_reason}/)
      expect(described_class.all_valid_ems_in_zone).to include(@ems)
    end

    it "returns an empty list for zone if timeline events are not supported" do
      expect_any_instance_of(@ems.class).to receive(:supports_timeline?).and_return(false)
      expect_any_instance_of(@ems.class).to receive(:unsupported_reason).and_return(unsupported_reason)
      expect($log).to receive(:info).with(/#{unsupported_reason}/)
      expect(described_class.all_valid_ems_in_zone).not_to include(@ems)
    end
  end
end
