describe ManageIQ::Providers::Azure::ContainerManager do
  it ".ems_type" do
    expect(described_class.ems_type).to eq('aks')
  end

  it ".description" do
    expect(described_class.description).to eq('Azure Kubernetes Service')
  end

  context "#pause!" do
    let(:zone) { FactoryBot.create(:zone) }
    let(:ems)  { FactoryBot.create(:ems_azure_aks, :zone => zone) }

    include_examples "ExtManagementSystem#pause!"
  end

  context "#resume!" do
    let(:zone) { FactoryBot.create(:zone) }
    let(:ems)  { FactoryBot.create(:ems_azure_aks, :zone => zone) }

    include_examples "ExtManagementSystem#resume!"
  end
end
