describe ManageIQ::Providers::Azure::NumberOfVmsVisibilityService do
  context "class information" do
    it "is a subclass of DialogVisibilityService" do
      expect(described_class.new).to be_kind_of(NumberOfVmsVisibilityService)
    end
  end

  context "NumberOfVmsVisibilityService" do
    subject { described_class.new }

    it "has a reader method for number_of_vms" do
      expect(subject).to respond_to(:number_of_vms)
    end

    it "defaults to 1 for the number of vms" do
      expect(described_class.new.number_of_vms).to eql(1)
    end

    it "returns the expected value for determine_visibility" do
      expect(subject.determine_visibility(1, 'azure')).to be_kind_of(Hash)
      expect(subject.determine_visibility(2, 'azure')[:hide]).to_not include(:floating_ip_addresses)
    end
  end
end
