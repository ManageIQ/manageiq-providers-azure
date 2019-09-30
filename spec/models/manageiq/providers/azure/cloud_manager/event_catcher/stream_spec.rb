describe ManageIQ::Providers::Azure::CloudManager::EventCatcher::Stream do
  let(:ems) { FactoryBot.create(:ems_azure_with_authentication) }
  let(:stream) { described_class.new(ems) }
  let(:connection) { double("Azure::Armrest::Insights::EventService") }
  before do
    allow(stream).to receive(:create_event_service).and_return(connection)
  end

  context "#get_events (private)" do
    let(:events) { [OpenStruct.new(:event_timestamp => "2019-09-30T11:20:00.0000000Z")] }
    before do
      allow(connection).to receive(:list).and_return(events)
    end

    context "first batch" do
      it "parses the maximum timestamp and sets it to @since" do
        stream.send(:get_events)

        expect(stream.since.to_s).to eq("2019-09-30T11:20:00+00:00")
      end
    end
  end
end
