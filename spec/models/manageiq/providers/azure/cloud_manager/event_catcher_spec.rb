describe ManageIQ::Providers::Azure::CloudManager::EventCatcher do
  context "valid ems" do
    let(:unsupported_reason) { "Timeline events not supported for this region" }

    before do
      @ems = FactoryBot.create(:ems_azure)
      allow(@ems).to receive(:authentication_status_ok?).and_return(true)
      allow(described_class).to receive(:all_ems_in_zone).and_return([@ems])
    end

    it "returns a valid ems for zone if timeline events are supported" do
      allow(@ems).to receive(:supports?).with(:timeline).and_return(true)
      expect($log).not_to receive(:info).with(/#{unsupported_reason}/)
      expect(described_class.all_valid_ems_in_zone).to include(@ems)
    end

    it "returns an empty list for zone if timeline events are not supported" do
      allow(@ems).to receive(:supports?).with(:timeline).and_return(false)
      allow(@ems).to receive(:unsupported_reason).and_return(unsupported_reason)
      expect($log).to receive(:info).with(/#{unsupported_reason}/)
      expect(described_class.all_valid_ems_in_zone).not_to include(@ems)
    end
  end
end
