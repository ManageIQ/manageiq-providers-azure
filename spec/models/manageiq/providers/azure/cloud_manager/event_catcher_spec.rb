describe ManageIQ::Providers::Azure::CloudManager::EventCatcher do
  context "valid ems" do
    let(:unsupported_reason) { "Timeline not supported for this region" }
    let(:zone) { EvmSpecHelper.local_guid_miq_server_zone.last }
    let!(:ems) { FactoryBot.create(:ems_azure, :with_authentication, :zone => zone, :capabilities => {"insights" => insights}) }

    context "with insights enabled" do
      let(:insights) { true }

      it "returns a valid ems for zone if timeline events are supported" do
        expect($log).not_to receive(:info).with(/#{unsupported_reason}/)
        expect(described_class.all_valid_ems_in_zone).to include(ems)
      end
    end

    context "with insights disabled" do
      let(:insights) { false }

      it "returns an empty list for zone if timeline events are not supported" do
        expect($log).to receive(:info).with(/#{unsupported_reason}/)
        expect(described_class.all_valid_ems_in_zone).not_to include(ems)
      end
    end
  end
end
