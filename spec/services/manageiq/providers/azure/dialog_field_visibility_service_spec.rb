describe ManageIQ::Providers::Azure::DialogFieldVisibilityService do
  context "class information" do
    it "is a subclass of DialogVisibilityService" do
      expect(described_class.new).to be_kind_of(DialogFieldVisibilityService)
    end
  end

  context "NumberOfVmsVisibilityService" do
    subject { described_class.new }

    it "has a reader method for number_of_vms_visibility_service" do
      expect(subject).to respond_to(:number_of_vms_visibility_service)
    end

    it "defaults to an Azure::NumberOfVmsVisibilityService instance" do
      expected_class = ManageIQ::Providers::Azure::NumberOfVmsVisibilityService
      expect(subject.number_of_vms_visibility_service).to be_kind_of(expected_class)
    end
  end
end
