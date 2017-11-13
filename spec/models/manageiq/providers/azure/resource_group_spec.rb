describe ManageIQ::Providers::Azure::ResourceGroup do
  context 'inheritance' do
    it 'is a subclass of ManageIQ::ResourceGroup' do
      expect(subject).to be_a_kind_of(ResourceGroup)
    end
  end
end
