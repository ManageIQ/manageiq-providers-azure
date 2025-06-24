describe ManageIQ::Providers::Azure::ContainerManager::Refresher do
  it ".ems_type" do
    expect(described_class.ems_type).to eq(:aks)
  end

  let(:zone) { EvmSpecHelper.create_guid_miq_server_zone.last }
  let!(:ems) do
    hostname = Rails.application.secrets.azure_aks[:hostname]

    FactoryBot.create(:ems_azure_aks, :hostname => hostname, :zone => zone).tap do |ems|
      token = Rails.application.secrets.azure_aks[:cluster_admin_token]
      ems.update_authentication(:bearer => {:auth_key => token})
    end
  end

  it "will perform a full refresh" do
    2.times do
      VCR.use_cassette(described_class.name.underscore) { EmsRefresh.refresh(ems) }

      ems.reload

      assert_table_counts
      assert_specific_container_project
      assert_specific_container_node
      assert_specific_container_service
      assert_specific_container_group
      assert_specific_container
      assert_specific_container_image
      assert_specific_container_image_registry
    end
  end

  def assert_table_counts
    expect(ems.container_projects.count).to         eq(4)
    expect(ems.container_nodes.count).to            eq(1)
    expect(ems.container_services.count).to         eq(4)
    expect(ems.container_groups.count).to           eq(11)
    expect(ems.containers.count).to                 eq(15)
    expect(ems.container_images.count).to           eq(11)
    expect(ems.container_image_registries.count).to eq(1)
  end

  def assert_specific_container_project
    expect(ems.container_projects.find_by(:name => "default")).to have_attributes(
      :type             => "ManageIQ::Providers::Azure::ContainerManager::ContainerProject",
      :name             => "default",
      :ems_ref          => "d6ed5673-46af-4166-a9b9-a794f0675098",
      :resource_version => "205"
    )
  end

  def assert_specific_container_node
    container_node = ems.container_nodes.find_by(:ems_ref => "5661a8d7-6bff-41ad-af17-a7f3388ac4fc")
    expect(container_node).to have_attributes(
      :name                       => "aks-agentpool-17806587-vmss000001",
      :ems_ref                    => "5661a8d7-6bff-41ad-af17-a7f3388ac4fc",
      :resource_version           => "1384166",
      :identity_infra             => "azure:///subscriptions/AZURE_SUBSCRIPTION_ID/resourceGroups/mc_agrare-resource-group_agrare-aks_eastus2/providers/Microsoft.Compute/virtualMachineScaleSets/aks-agentpool-17806587-vmss/virtualMachines/1",
      :identity_machine           => "45b94979343b410ea46aa3f1f7cdc626",
      :identity_system            => "ef3e3584-8efb-4327-b1f0-ff741d993cde",
      :type                       => "ManageIQ::Providers::Azure::ContainerManager::ContainerNode",
      :kubernetes_kubelet_version => "v1.21.2",
      :kubernetes_proxy_version   => "v1.21.2",
      :container_runtime_version  => "containerd://1.4.8+azure"
    )

    expect(container_node.container_groups.count).to eq(11)
    expect(container_node.containers.count).to eq(15)
  end

  def assert_specific_container_service
    container_service = ems.container_services.find_by(:name => "kube-dns")
    expect(container_service).to have_attributes(
      :ems_ref          => "064c713f-6e88-4947-baf1-21f57a6b2902",
      :name             => "kube-dns",
      :resource_version => "450",
      :session_affinity => "None",
      :portal_ip        => "10.0.0.10",
      :service_type     => "ClusterIP"
    )

    expect(container_service.container_project.name).to eq("kube-system")
    expect(container_service.container_groups.count).to eq(2)
  end

  def assert_specific_container_group
    container_group = ems.container_groups.find_by(:ems_ref => "f0b17c05-0ae3-4258-8aed-322c224347c1")
    expect(container_group).to have_attributes(
      :ems_ref          => "f0b17c05-0ae3-4258-8aed-322c224347c1",
      :name             => "azure-ip-masq-agent-7bln9",
      :resource_version => "945",
      :restart_policy   => "Always",
      :dns_policy       => "ClusterFirst",
      :ipaddress        => "10.240.0.5",
      :type             => "ManageIQ::Providers::Azure::ContainerManager::ContainerGroup",
      :phase            => "Running"
    )

    expect(container_group.container_project.name).to eq("kube-system")
    expect(container_group.container_node.name).to    eq("aks-agentpool-17806587-vmss000001")
    expect(container_group.containers.count).to       eq(1)
  end

  def assert_specific_container
    container = ems.containers.find_by(:ems_ref => "f0b17c05-0ae3-4258-8aed-322c224347c1_azure-ip-masq-agent_mcr.microsoft.com/oss/kubernetes/ip-masq-agent:v2.5.0.6")
    expect(container).to have_attributes(
      :ems_ref              => "f0b17c05-0ae3-4258-8aed-322c224347c1_azure-ip-masq-agent_mcr.microsoft.com/oss/kubernetes/ip-masq-agent:v2.5.0.6",
      :name                 => "azure-ip-masq-agent",
      :restart_count        => 0,
      :state                => "running",
      :backing_ref          => "containerd://8d1cdae0db7ae374347b6ccc718267e96f7cef413c946a9369316e379b066d78",
      :type                 => "ManageIQ::Providers::Azure::ContainerManager::Container",
      :request_cpu_cores    => 0.1,
      :request_memory_bytes => 50.megabytes,
      :limit_cpu_cores      => 0.5,
      :limit_memory_bytes   => 250.megabytes,
      :image                => "mcr.microsoft.com/oss/kubernetes/ip-masq-agent:v2.5.0.6",
      :image_pull_policy    => "IfNotPresent"
    )

    expect(container.container_project.name).to eq("kube-system")
    expect(container.container_node.name).to    eq("aks-agentpool-17806587-vmss000001")
    expect(container.container_group.name).to   eq("azure-ip-masq-agent-7bln9")
    expect(container.container_image.name).to   eq("oss/kubernetes/ip-masq-agent")
  end

  def assert_specific_container_image
    container_image = ems.container_images.find_by(:name => "oss/kubernetes/ip-masq-agent")
    expect(container_image).to have_attributes(
      :name                     => "oss/kubernetes/ip-masq-agent",
      :image_ref                => "docker://mcr.microsoft.com/oss/kubernetes/ip-masq-agent",
      :container_image_registry => ems.container_image_registries.find_by(:name => "mcr.microsoft.com"),
      :type                     => "ContainerImage"
    )
  end

  def assert_specific_container_image_registry
    container_image_registry = ems.container_image_registries.find_by(:name => "mcr.microsoft.com")
    expect(container_image_registry).to have_attributes(
      :name => "mcr.microsoft.com",
      :host => "mcr.microsoft.com"
    )
  end
end
