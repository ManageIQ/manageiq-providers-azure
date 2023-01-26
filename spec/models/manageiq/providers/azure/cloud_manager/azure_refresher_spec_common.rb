module AzureRefresherSpecCommon
  extend ActiveSupport::Concern

  ALL_REFRESH_SETTINGS = [
    {
      :get_private_images       => true,
      :inventory_collections    => {
        :saver_strategy => "default",
      },
    }, {
      :get_private_images       => true,
      :inventory_collections    => {
        :saver_strategy => "batch",
        :use_ar_object  => false,
      },
    }
  ].freeze

  GRAPH_REFRESH_ADDITIONAL_SETTINGS = [
    {
      :targeted_api_collection_threshold => 0,
    }, {
      :targeted_api_collection_threshold => 500,
    }
  ].freeze

  MODELS = %i(
    ext_management_system flavor availability_zone vm_or_template vm miq_template disk guest_device
    hardware network operating_system relationship orchestration_template orchestration_stack
    orchestration_stack_parameter orchestration_stack_output orchestration_stack_resource security_group
    network_port cloud_network floating_ip network_router cloud_subnet resource_group load_balancer
    load_balancer_pool load_balancer_pool_member load_balancer_pool_member_pool load_balancer_listener
    load_balancer_listener_pool load_balancer_health_check load_balancer_health_check_member cloud_database
  ).freeze

  def refresh_with_cassette(targets, suffix)
    @ems.reload

    name = described_class.name.underscore
    # We need different VCR for GraphRefresh
    name += suffix

    # Must decode compressed response for subscription id.
    VCR.use_cassette(name, :allow_unused_http_interactions => true, :decode_compressed_response => true) do
      EmsRefresh.refresh(targets)
    end

    @ems.reload
  end

  def setup_ems_and_cassette(refresh_settings)
    stub_with_current_settings(refresh_settings)
    @ems.reload

    name = described_class.name.underscore
    name += '_inventory_object'

    # Must decode compressed response for subscription id.
    VCR.use_cassette(name, :allow_unused_http_interactions => true, :decode_compressed_response => true) do
      EmsRefresh.refresh(@ems)
    end

    ::Azure::Armrest::Configuration.clear_caches
    @ems.reload
  end

  def define_shared_variables
    _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone

    @ems = FactoryBot.create(:ems_azure_with_vcr_authentication, :zone => zone, :provider_region => 'eastus')

    @vm_group             = 'miq-vms-eastus'
    @network_group        = 'miq-networking-eastus'
    @misc_group           = 'miq-misc-eastus'
    @ubuntu_east          = 'miq-vm-ubuntu1-eastus' # Power on before regenerating cassettes
    @centos_east          = 'miq-vm-centos1-eastus' # Power off before regenerating cassettes
    @rhel_east            = 'miq-vm-rhel2-mismatch'
    @security_group       = 'miq-nsg-eastus1'
    @centos_public_ip     = 'miq-publicip-eastus2'
    @unmanaged_disk       = 'miq-vm-centos-disk1'
    @cloud_network        = 'miq-vnet-eastus'
    @network_interface    = 'miq-nic-eastus1'
    @managed_vm           = 'miq-vm-sles1-eastus'
    @managed_os_disk      = 'miq-vm-sles1-disk'
    @managed_data_disk    = 'miq-data-disk-eastus1'
    @route_table          = 'miq-route-table-eastus1'
    @vm_from_image        = 'miq-vm-from-image-eastus1'
    @image_name           = 'miq-linux-img-east'
    @load_balancer        = 'miq-lb-eastus'
    @load_balancer_no_mem = 'miq-lb-eastus2'
    @backend_pool         = 'miq-backend-pool1'
    @vm_lb1               = 'miq-vm1-lb-eastus'
    @vm_lb2               = 'miq-vm2-lb-eastus'
    @lb_ip_address        = '40.76.218.17'  # Update after restart
    @ubuntu_ip_address    = '40.114.95.228' # Update after restart
    @orch_template        = 'miq-template-eastus'
    @creator              = 'dberger' # Update as needed

    @vm_powered_on = @ubuntu_east
    @vm_powered_off = @centos_east
    @vm_in_other_region = "miq-vm-ubuntu1-eastus2"
    @disk_powered_on = 'miq-vm-ubuntu-disk1'

    FactoryBot.create(:tag_mapping_with_category,
                       :labeled_resource_type => 'VmAzure',
                       :label_name            => 'Shutdown',
                       :category_name         => 'azure:vm:shutdown')
  end

  def stub_with_current_settings(current_settings)
    stub_settings_merge(
      :ems_refresh => {
        :azure         => current_settings,
        :azure_network => current_settings,
      }
    )
  end

  def serialize_inventory
    skip_atributes = %w(updated_on last_refresh_date updated_at last_updated finish_time)
    inventory = {}
    AzureRefresherSpecCommon::MODELS.each do |rel|
      inventory[rel] = rel.to_s.classify.constantize.all.collect do |e|
        e.attributes.except(*skip_atributes)
      end
    end

    inventory
  end

  def assert_models_not_changed(inventory_before, inventory_after)
    aggregate_failures do
      AzureRefresherSpecCommon::MODELS.each do |model|
        # TODO(lsmola) solve special handling for :load_balancer_pool, that differs from old refresh
        next if model == :load_balancer_pool

        expect(inventory_after[model].count).to eq(inventory_before[model].count), "#{model} count"\
               " doesn't fit \nexpected: #{inventory_before[model].count}\ngot#{inventory_after[model].count}"

        inventory_after[model].each do |item_after|
          item_before = inventory_before[model].detect { |i| i["id"] == item_after["id"] }
          expect(item_after).to eq(item_before), \
                                "class: #{model.to_s.classify}\nexpected: #{item_before}\ngot: #{item_after}"
        end
      end
    end
  end

  def expected_table_counts
    {
      :availability_zone                 => 1,
      :cloud_database                    => 9,
      :cloud_network                     => 3,
      :cloud_subnet                      => 3,
      :disk                              => 11,
      :ext_management_system             => 2,
      :flavor                            => 198,
      :floating_ip                       => 9,
      :guest_device                      => 0,
      :hardware                          => 21,
      :load_balancer                     => 2,
      :load_balancer_pool                => 1,
      :load_balancer_pool_member         => 2,
      :load_balancer_pool_member_pool    => 2,
      :load_balancer_listener            => 1,
      :load_balancer_listener_pool       => 1,
      :load_balancer_health_check        => 3,
      :load_balancer_health_check_member => 2,
      :miq_template                      => 12,
      :network                           => 16,
      :network_port                      => 11,
      :network_router                    => 1,
      :operating_system                  => 10,
      :orchestration_stack               => 12,
      :orchestration_stack_output        => 2,
      :orchestration_stack_parameter     => 13,
      :orchestration_stack_resource      => 15,
      :orchestration_template            => 12,
      :relationship                      => 0,
      :resource_group                    => 8,
      :security_group                    => 5,
      :vm                                => 9,
      :vm_or_template                    => 21,
    }
  end

  def assert_counts(counts)
    assert_table_counts(base_expected_table_counts.merge(counts))
  end

  def base_expected_table_counts
    Hash[MODELS.collect { |m| [m, 0] }]
  end

  def actual_table_counts
    Hash[MODELS.collect { |m| [m, m.to_s.classify.constantize.count] }]
  end

  def assert_table_counts(passed_counts = nil)
    expect(actual_table_counts).to eq(passed_counts || expected_table_counts)
  end

  def assert_ems
    expect(@ems.flavors.size).to eql(expected_table_counts[:flavor])
    expect(@ems.availability_zones.size).to eql(expected_table_counts[:availability_zone])
    expect(@ems.vms_and_templates.size).to eql(expected_table_counts[:vm_or_template])
    expect(@ems.security_groups.size).to eql(expected_table_counts[:security_group])
    expect(@ems.network_ports.size).to eql(expected_table_counts[:network_port])
    expect(@ems.cloud_networks.size).to eql(expected_table_counts[:cloud_network])
    expect(@ems.floating_ips.size).to eql(expected_table_counts[:floating_ip])
    expect(@ems.network_routers.size).to eql(expected_table_counts[:network_router])
    expect(@ems.cloud_subnets.size).to eql(expected_table_counts[:cloud_subnet])
    expect(@ems.miq_templates.size).to eq(expected_table_counts[:miq_template])

    expect(@ems.orchestration_stacks.size).to eql(expected_table_counts[:orchestration_stack])
    expect(@ems.direct_orchestration_stacks.size).to eql(11)
  end

  def assert_specific_load_balancers
    lb_ems_ref = "/subscriptions/#{@ems.subscription}/resourceGroups/#{@network_group}"\
                   "/providers/Microsoft.Network/loadBalancers/#{@load_balancer}"

    lb_pool_ems_ref = "/subscriptions/#{@ems.subscription}/resourceGroups/#{@network_group}"\
                        "/providers/Microsoft.Network/loadBalancers/#{@load_balancer}/backendAddressPools/#{@backend_pool}"

    lb = ManageIQ::Providers::Azure::NetworkManager::LoadBalancer.find_by(:name => @load_balancer)

    lb_no_members = ManageIQ::Providers::Azure::NetworkManager::LoadBalancer.find_by(:name => @load_balancer_no_mem)

    pool = ManageIQ::Providers::Azure::NetworkManager::LoadBalancerPool.find_by(:ems_ref => lb_pool_ems_ref)

    expect(lb).to have_attributes(
      'ems_ref'         => lb_ems_ref,
      'name'            => @load_balancer,
      'description'     => nil,
      'cloud_tenant_id' => nil,
      'type'            => 'ManageIQ::Providers::Azure::NetworkManager::LoadBalancer'
    )

    expect(lb.ext_management_system).to eq(@ems.network_manager)
    expect(lb.vms.count).to eq(2)
    expect(lb.load_balancer_pools.first).to eq(pool)
    expect(lb.load_balancer_pool_members.count).to eq(2)
    expect(lb.load_balancer_pool_members.first.ext_management_system).to eq(@ems.network_manager)
    expect(lb.vms.first.ext_management_system).to eq(@ems)
    expect(lb.vms.collect(&:name).sort).to match_array(['miq-vm1-lb-eastus', 'miq-vm2-lb-eastus'])
    expect(lb_no_members.load_balancer_pool_members.count).to eq(0)
  end

  def assert_specific_load_balancer_networking
    lb = ManageIQ::Providers::Azure::NetworkManager::LoadBalancer.find_by(:name => @load_balancer)
    floating_ip = FloatingIp.find_by(:address => @lb_ip_address)

    expect(lb).to eq(floating_ip.network_port.device)
  end

  def assert_specific_load_balancer_listeners
    lb_listener_ems_ref = "/subscriptions/#{@ems.subscription}/resourceGroups/#{@network_group}"\
                            "/providers/Microsoft.Network/loadBalancers/#{@load_balancer}"\
                            "/loadBalancingRules/miq-lb-rule1"

    lb_pool_ems_ref = "/subscriptions/#{@ems.subscription}/resourceGroups/#{@network_group}"\
                        "/providers/Microsoft.Network/loadBalancers/#{@load_balancer}/backendAddressPools/#{@backend_pool}"

    lb_pool_member_1_ems_ref = "/subscriptions/#{@ems.subscription}/resourceGroups/#{@network_group}"\
                                 "/providers/Microsoft.Network/networkInterfaces/miq-nic1-lb-eastus"\
                                 "/ipConfigurations/ipconfig1"

    lb_pool_member_2_ems_ref = "/subscriptions/#{@ems.subscription}/resourceGroups/#{@network_group}"\
                                 "/providers/Microsoft.Network/networkInterfaces/miq-nic2-lb-eastus"\
                                 "/ipConfigurations/ipconfig1"

    lb = ManageIQ::Providers::Azure::NetworkManager::LoadBalancer.find_by(:name => @load_balancer)
    listener = ManageIQ::Providers::Azure::NetworkManager::LoadBalancerListener.find_by(:ems_ref => lb_listener_ems_ref)
    pool = ManageIQ::Providers::Azure::NetworkManager::LoadBalancerPool.find_by(:ems_ref => lb_pool_ems_ref)
    lb_no_members = ManageIQ::Providers::Azure::NetworkManager::LoadBalancer.find_by(:name => @load_balancer_no_mem)

    expect(listener).to have_attributes(
      'ems_ref'                  => lb_listener_ems_ref,
      'name'                     => nil,
      'description'              => nil,
      'load_balancer_protocol'   => 'Tcp',
      'load_balancer_port_range' => 80...81,
      'instance_protocol'        => 'Tcp',
      'instance_port_range'      => 80...81,
      'cloud_tenant_id'          => nil,
      'type'                     => 'ManageIQ::Providers::Azure::NetworkManager::LoadBalancerListener'
    )

    expect(listener.ext_management_system).to eq(@ems.network_manager)
    expect(lb.load_balancer_listeners).to eq [listener]
    expect(listener.load_balancer_pools).to eq([pool])
    expect(listener.load_balancer_pool_members.collect(&:ems_ref).sort)
      .to match_array [lb_pool_member_1_ems_ref, lb_pool_member_2_ems_ref]

    expect(listener.vms.collect(&:name).sort).to match_array(['miq-vm1-lb-eastus', 'miq-vm2-lb-eastus'])
    expect(lb_no_members.load_balancer_listeners.count).to eq(0)
  end

  def assert_specific_load_balancer_health_checks
    health_check_ems_ref = "/subscriptions/#{@ems.subscription}/resourceGroups/#{@network_group}"\
                             "/providers/Microsoft.Network/loadBalancers/#{@load_balancer}"\
                             "/probes/miq-lb-health-probe1"

    lb_listener_ems_ref = "/subscriptions/#{@ems.subscription}/resourceGroups/#{@network_group}"\
                            "/providers/Microsoft.Network/loadBalancers/#{@load_balancer}"\
                            "/loadBalancingRules/miq-lb-rule1"

    lb = ManageIQ::Providers::Azure::NetworkManager::LoadBalancer.find_by(:name => @load_balancer)
    health_check = ManageIQ::Providers::Azure::NetworkManager::LoadBalancerHealthCheck.find_by(:ems_ref => health_check_ems_ref)
    lb_no_members = ManageIQ::Providers::Azure::NetworkManager::LoadBalancer.find_by(:name => @load_balancer_no_mem)
    listener = ManageIQ::Providers::Azure::NetworkManager::LoadBalancerListener.find_by(:ems_ref => lb_listener_ems_ref)

    expect(health_check).to have_attributes(
      'ems_ref'         => health_check_ems_ref,
      'name'            => nil,
      'protocol'        => 'Http',
      'port'            => 80,
      'url_path'        => '/',
      'interval'        => 15,
      'cloud_tenant_id' => nil,
      'type'            => 'ManageIQ::Providers::Azure::NetworkManager::LoadBalancerHealthCheck'
    )
    expect(listener.load_balancer_health_checks.first).to eq(health_check)
    expect(health_check.load_balancer).to eq(lb)
    expect(health_check.load_balancer_health_check_members.count).to eq(2)
    expect(health_check.load_balancer_pool_members.count).to eq(2)
    expect(lb_no_members.load_balancer_health_checks.count).to eq(1)
  end

  def assert_specific_router
    router = ManageIQ::Providers::Azure::NetworkManager::NetworkRouter.where(:name => @route_table).first

    expect(router).to have_attributes(
      :name             => @route_table,
      :status           => 'inactive',
      :type             => 'ManageIQ::Providers::Azure::NetworkManager::NetworkRouter',
      :extra_attributes => {
        :routes => [
          {
            'Name'           => 'miq-route-eastus1',
            'Resource Group' => @network_group,
            'CIDR'           => '10.0.0.0/16'
          }
        ]
      }
    )
  end

  def assert_specific_security_group
    sg = ManageIQ::Providers::Azure::NetworkManager::SecurityGroup.find_by(:name => @security_group)

    expect(sg).to have_attributes(
      :name        => @security_group,
      :description => 'miq-networking-eastus-eastus'
    )

    expected_firewall_rules = [
      {:host_protocol => 'TCP', :direction => 'Inbound', :port => 22,  :end_port => 22,  :source_ip_range => '*'},
      {:host_protocol => 'TCP', :direction => 'Inbound', :port => 80,  :end_port => 80,  :source_ip_range => '*'},
      {:host_protocol => 'TCP', :direction => 'Inbound', :port => 443, :end_port => 443, :source_ip_range => '*'}
    ]

    expect(sg.firewall_rules.size).to eq(3)

    sg.firewall_rules
      .order(:host_protocol, :direction, :port, :end_port, :source_ip_range, :source_security_group_id)
      .zip(expected_firewall_rules)
      .each do |actual, expected|
      expect(actual).to have_attributes(expected)
    end
  end

  def assert_specific_flavor(managed = false)
    if managed
      flavor = ManageIQ::Providers::Azure::CloudManager::Flavor.find_by(:ems_ref => 'standard_a0')
      name = 'Standard_A0'
      memory = 768.megabytes
      root_disk_size = 1_047_552.megabytes
      swap_disk_size = 20_480.megabytes
    else
      flavor = ManageIQ::Providers::Azure::CloudManager::Flavor.find_by(:ems_ref => 'standard_b1s')
      name = 'Standard_B1s'
      memory = 1024.megabytes
      root_disk_size = 1_047_552.megabytes
      swap_disk_size = 2048.megabytes
    end

    expect(flavor).to have_attributes(
      :name                     => name,
      :description              => nil,
      :enabled                  => true,
      :cpu_total_cores          => 1,
      :memory                   => memory,
      :supports_32_bit          => nil,
      :supports_64_bit          => nil,
      :supports_hvm             => nil,
      :supports_paravirtual     => nil,
      :block_storage_based_only => nil,
      :root_disk_size           => root_disk_size,
      :swap_disk_size           => swap_disk_size
    )

    expect(flavor.ext_management_system).to eq(@ems)
  end

  def assert_specific_az
    avail_zone = ManageIQ::Providers::Azure::CloudManager::AvailabilityZone.first
    expect(avail_zone).to have_attributes(:name => @ems.name)
  end

  def assert_specific_cloud_network
    cn_resource_id = "/subscriptions/#{@ems.subscription}"\
                         "/resourceGroups/#{@network_group}/providers/Microsoft.Network"\
                         "/virtualNetworks/#{@cloud_network}"

    cloud_network = CloudNetwork.find_by(:name => @cloud_network)
    availability_zone = ManageIQ::Providers::Azure::CloudManager::AvailabilityZone.first

    expect(cloud_network).to have_attributes(
      :name    => @cloud_network,
      :ems_ref => cn_resource_id,
      :cidr    => '10.0.0.0/16',
      :status  => nil,
      :enabled => true
    )

    expect(cloud_network.vms.size).to be >= 1
    expect(cloud_network.network_ports.size).to be >= 1

    vm = cloud_network.vms.find_by(:name => @ubuntu_east)
    expect(vm.cloud_networks.size).to be >= 1

    expect(cloud_network.cloud_subnets.size).to eq(1)

    subnet = cloud_network.cloud_subnets.find_by(:name => 'default')

    expect(subnet).to have_attributes(
      :name              => 'default',
      :ems_ref           => "#{cn_resource_id}/subnets/default",
      :cidr              => '10.0.0.0/24',
      :availability_zone => availability_zone
    )

    vm_subnet = subnet.vms.find_by(:name => @ubuntu_east)

    expect(vm_subnet.cloud_subnets.size).to be >= 1
    expect(vm_subnet.network_ports.size).to be >= 1
    expect(vm_subnet.security_groups.size).to be >= 1
    expect(vm_subnet.floating_ips.size).to be >= 1
  end

  def assert_specific_vm_powered_on
    vm = ManageIQ::Providers::Azure::CloudManager::Vm.find_by(:name => @ubuntu_east)
    avail_zone = ManageIQ::Providers::Azure::CloudManager::AvailabilityZone.first
    flavor = ManageIQ::Providers::Azure::CloudManager::Flavor.find_by(:ems_ref => 'standard_b1s')

    vm_resource_id = "#{@ems.subscription}/#{@vm_group}/microsoft.compute/virtualmachines/#{@ubuntu_east}"

    expect(vm).to have_attributes(
      :template              => false,
      :ems_ref               => vm_resource_id,
      :uid_ems               => '659e936f-a83c-4b87-9467-5393527d24d9',
      :vendor                => 'azure',
      :power_state           => 'on',
      :raw_power_state       => 'VM running',
      :location              => 'eastus',
      :tools_status          => nil,
      :boot_time             => nil,
      :standby_action        => nil,
      :connection_state      => "connected",
      :cpu_affinity          => nil,
      :memory_reserve        => nil,
      :memory_reserve_expand => nil,
      :memory_limit          => nil,
      :memory_shares         => nil,
      :memory_shares_level   => nil,
      :cpu_reserve           => nil,
      :cpu_reserve_expand    => nil,
      :cpu_limit             => nil,
      :cpu_shares            => nil,
      :cpu_shares_level      => nil
    )

    expect(vm.ext_management_system).to eql(@ems)
    expect(vm.availability_zone).to eql(avail_zone)
    expect(vm.flavor).to eql(flavor)
    expect(vm.operating_system.product_name).to eql('UbuntuServer 16.04 LTS')
    expect(vm.custom_attributes.size).to eql(3)
    expect(vm.snapshots.size).to eql(0)

    aggregate_failures do
      expect(vm.labels.pluck(:name, :value).to_h).to eq('creator' => @creator, 'specs' => 'true', 'owner' => 'cfme')
      # expect(vm.tags.pluck(:name)).to eq(%w(/managed/azure:vm:shutdown/true))
    end

    assert_specific_vm_powered_on_hardware(vm)
  end

  def assert_specific_vm_powered_on_hardware(v)
    expect(v.hardware).to have_attributes(
      :guest_os            => nil,
      :guest_os_full_name  => nil,
      :bios                => nil,
      :annotation          => nil,
      :cpu_total_cores     => 1,
      :memory_mb           => 1024,
      :disk_capacity       => 1025.gigabytes,
      :bitness             => nil,
      :virtualization_type => nil
    )

    expect(v.hardware.guest_devices.size).to eql(0)
    expect(v.hardware.nics.size).to eql(0)

    floating_ip = ManageIQ::Providers::Azure::NetworkManager::FloatingIp.find_by(:address => @ubuntu_ip_address)
    cloud_network = ManageIQ::Providers::Azure::NetworkManager::CloudNetwork.find_by(:name => @cloud_network)

    cloud_subnet = cloud_network.cloud_subnets.first
    expect(v.floating_ip).to eql(floating_ip)
    expect(v.floating_ips.first).to eql(floating_ip)
    expect(v.floating_ip_addresses.first).to eql(floating_ip.address)
    expect(v.fixed_ip_addresses).to match_array(v.ipaddresses - [floating_ip.address])
    expect(v.fixed_ip_addresses.count).to be > 0

    expect(v.cloud_network).to eql(cloud_network)
    expect(v.cloud_subnet).to eql(cloud_subnet)

    assert_specific_hardware_networks(v)
  end

  def assert_specific_hardware_networks(v)
    expect(v.hardware.networks.size).to eql(2)
    network = v.hardware.networks.where(:description => "public").first
    expect(network).to have_attributes(
      :description => 'public',
      :ipaddress   => @ubuntu_ip_address,
      :hostname    => 'ipconfig1'
    )
    network = v.hardware.networks.where(:description => "private").first
    expect(network).to have_attributes(
      :description => 'private',
      :ipaddress   => '10.0.0.4',
      :hostname    => 'ipconfig1'
    )
  end

  def assert_specific_disk
    uri  = "https://miqunmanagedeastus.blob.core.windows.net/vhds/#{@disk_powered_on}.vhd"
    disk = Disk.find_by(:device_name => @disk_powered_on)

    expect(disk).to have_attributes(
      :location => uri,
      #:mode     => 'Standard_RAGRS',
      :size     => 32_212_254_720 # 30gb, approx
    )
  end

  def assert_specific_vm_with_managed_disks
    vm = Vm.find_by(:name => @managed_vm)
    expect(vm.disks.size).to eq(2)
    expect(vm.disks.collect(&:device_name)).to match_array([@managed_os_disk, @managed_data_disk])
  end

  def assert_specific_managed_disk
    disk = Disk.find_by(:device_name => @managed_os_disk)
    expect(disk.location.downcase).to eql("/subscriptions/#{@ems.subscription}/resourceGroups/"\
                                   "#{@vm_group}/providers/Microsoft.Compute/disks/"\
                                   "#{@managed_os_disk}".downcase)
    expect(disk.size).to eql(30.gigabytes)
    expect(disk.mode).to eql('Standard_LRS')
  end

  def assert_specific_resource_group
    vm_same_region = Vm.find_by(:name => @ubuntu_east)
    vm_diff_region = Vm.find_by(:name => @rhel_east)

    group_same_region = ResourceGroup.find_by(:name => 'miq-vms-eastus')
    group_diff_region = ResourceGroup.find_by(:name => 'miq-vms-westus')

    expect(vm_same_region.resource_group).to eql(group_same_region)
    expect(vm_diff_region.resource_group).to eql(group_diff_region)
  end

  def assert_specific_vm_powered_off
    vm = ManageIQ::Providers::Azure::CloudManager::Vm.find_by(
      :name            => @centos_east,
      :raw_power_state => 'VM deallocated'
    )

    availability_zone = ManageIQ::Providers::Azure::CloudManager::AvailabilityZone.first
    floating_ip       = ManageIQ::Providers::Azure::NetworkManager::FloatingIp.find_by(:name => @centos_public_ip)
    cloud_network     = ManageIQ::Providers::Azure::NetworkManager::CloudNetwork.find_by(:name => @cloud_network)
    cloud_subnet      = cloud_network.cloud_subnets.first

    assert_specific_vm_powered_off_attributes(vm)

    expect(vm.ext_management_system).to eql(@ems)
    expect(vm.availability_zone).to eql(availability_zone)
    expect(vm.floating_ip).to eql(floating_ip)
    expect(vm.cloud_network).to eql(cloud_network)
    expect(vm.cloud_subnet).to eql(cloud_subnet)
    expect(vm.operating_system.product_name).to eql('CentOS 7.3')
    expect(vm.custom_attributes.size).to eql(3)
    expect(vm.snapshots.size).to eql(0)

    labels = {
      'creator' => 'dberger',
      'owner'   => 'cfme',
      'specs'   => 'true'
    }

    aggregate_failures do
      expect(vm.labels.pluck(:name, :value).to_h).to eq(labels)
      # expect(vm.tags.pluck(:name)).to eq(%w(/managed/azure:vm:shutdown/true))
    end

    assert_specific_vm_powered_off_hardware(vm)
  end

  def assert_specific_vm_powered_off_attributes(vm)
    vm_resource_id = "#{@ems.subscription}/#{@vm_group}/microsoft.compute/virtualmachines/#{@centos_east}"

    expect(vm).to have_attributes(
      :template              => false,
      :ems_ref               => vm_resource_id,
      :uid_ems               => '1cdd5a0f-8aca-4e32-b24c-c2f25c7c60e0',
      :vendor                => 'azure',
      :power_state           => 'off',
      :location              => 'eastus',
      :tools_status          => nil,
      :boot_time             => nil,
      :standby_action        => nil,
      :connection_state      => "connected",
      :cpu_affinity          => nil,
      :memory_reserve        => nil,
      :memory_reserve_expand => nil,
      :memory_limit          => nil,
      :memory_shares         => nil,
      :memory_shares_level   => nil,
      :cpu_reserve           => nil,
      :cpu_reserve_expand    => nil,
      :cpu_limit             => nil,
      :cpu_shares            => nil,
      :cpu_shares_level      => nil
    )
  end

  def assert_specific_vm_powered_off_hardware(vm)
    expect(vm.hardware).to have_attributes(
      :guest_os           => nil,
      :guest_os_full_name => nil,
      :bios               => nil,
      :annotation         => nil,
      :cpu_sockets        => 1,
      :memory_mb          => 1024,
      :disk_capacity      => 1_100_585_369_600,
      :bitness            => nil
    )

    expect(vm.hardware.disks.size).to eql(1)
    expect(vm.hardware.guest_devices.size).to eql(0)
    expect(vm.hardware.nics.size).to eql(0)
    expect(vm.hardware.networks.size).to eql(2)
  end

  def assert_specific_parent
    template_resource_id = "/subscriptions/#{@ems.subscription}/resourcegroups/#{@vm_group}"\
                           "/providers/microsoft.compute/images/#{@image_name}"

    vm_resource_id = "#{@ems.subscription}/#{@vm_group}/microsoft.compute/virtualmachines/#{@vm_from_image}"

    vm = ManageIQ::Providers::Azure::CloudManager::Vm.find_by(:ems_ref => vm_resource_id)
    template = ManageIQ::Providers::Azure::CloudManager::Template.find_by(:ems_ref => template_resource_id)

    expect(vm.parent).to eql(template)
  end

  def assert_specific_template
    template_ems_ref = "/subscriptions/#{@ems.subscription}/resourcegroups/#{@vm_group}"\
                         "/providers/microsoft.compute/images/#{@image_name}"

    template = ManageIQ::Providers::Azure::CloudManager::Template.find_by(:ems_ref => template_ems_ref)

    expect(template).to have_attributes(
      :template              => true,
      :ems_ref               => template_ems_ref,
      :uid_ems               => template_ems_ref,
      :vendor                => 'azure',
      :power_state           => 'never',
      :location              => 'eastus',
      :tools_status          => nil,
      :boot_time             => nil,
      :standby_action        => nil,
      :connection_state      => "connected",
      :cpu_affinity          => nil,
      :memory_reserve        => nil,
      :memory_reserve_expand => nil,
      :memory_limit          => nil,
      :memory_shares         => nil,
      :memory_shares_level   => nil,
      :cpu_reserve           => nil,
      :cpu_reserve_expand    => nil,
      :cpu_limit             => nil,
      :cpu_shares            => nil,
      :cpu_shares_level      => nil
    )

    expect(template.ext_management_system).to eq(@ems)
    expect(template.operating_system.product_name).to eq('Linux')
    expect(template.custom_attributes.size).to eq(0)
    expect(template.snapshots.size).to eq(0)

    expect(template.hardware).to have_attributes(
      :guest_os            => 'linux_generic',
      :guest_os_full_name  => nil,
      :bios                => nil,
      :annotation          => nil,
      :memory_mb           => nil,
      :disk_capacity       => nil,
      :bitness             => 64,
      :virtualization_type => nil,
      :root_device_type    => nil
    )

    expect(template.hardware.disks.size).to eq(0)
    expect(template.hardware.guest_devices.size).to eq(0)
    expect(template.hardware.nics.size).to eq(0)
    expect(template.hardware.networks.size).to eq(0)
  end

  def assert_specific_orchestration_template
    template = ManageIQ::Providers::Azure::CloudManager::OrchestrationTemplate.find_by(:name => @orch_template)

    expect(template.name).to eql(@orch_template)
    expect(template.description).to start_with('contentVersion:')
    expect(template.content).to start_with("{\"$schema\":\"https://schema.management.azure.com"\
          "/schemas/2015-01-01/deploymentTemplate.json")
  end

  def assert_specific_orchestration_stack
    orch_stack = ManageIQ::Providers::Azure::CloudManager::OrchestrationStack.find_by(:name => @orch_template)

    expect(orch_stack).to have_attributes(
      :status         => 'Succeeded',
      :description    => @orch_template,
      :resource_group => @misc_group,
      :ems_ref        => "/subscriptions/#{@ems.subscription}/resourceGroups/#{@misc_group}"\
        "/providers/Microsoft.Resources/deployments/#{@orch_template}"
    )

    assert_specific_orchestration_stack_parameters
    assert_specific_orchestration_stack_resources
    assert_specific_orchestration_stack_outputs
    assert_specific_orchestration_stack_associations
  end

  def assert_specific_orchestration_stack_parameters
    orch_stack = ManageIQ::Providers::Azure::CloudManager::OrchestrationStack.find_by(:name => @orch_template)
    parameters = orch_stack.parameters.order('ems_ref')
    expect(parameters.size).to eq(5)

    admin_param = parameters.find { |param| param.name == 'adminUsername' }

    expect(admin_param).to have_attributes(
      :value   => 'miq-admin-username',
      :ems_ref => "/subscriptions/#{@ems.subscription}/resourceGroups/#{@misc_group}"\
        "/providers/Microsoft.Resources/deployments/#{@orch_template}/adminUsername"
    )
  end

  def assert_specific_orchestration_stack_resources
    orch_stack = ManageIQ::Providers::Azure::CloudManager::OrchestrationStack.find_by(:name => @orch_template)
    resources = orch_stack.resources.order('ems_ref')
    expect(resources.size).to eq(4)
    name = 'miq-availability-set-deployment-eastus'

    availability_set = resources.find { |res| res.name == name }

    expect(availability_set).to have_attributes(
      :logical_resource       => name,
      :resource_category      => 'Microsoft.Compute/availabilitySets',
      :resource_status        => 'Succeeded',
      :resource_status_reason => 'OK',
      :ems_ref                => "/subscriptions/#{@ems.subscription}/resourceGroups/#{@misc_group}"\
                                   "/providers/Microsoft.Compute/availabilitySets/#{name}"
    )
  end

  def assert_specific_orchestration_stack_outputs
    outputs = ManageIQ::Providers::Azure::CloudManager::OrchestrationStack.find_by(:name => @orch_template).outputs
    name = 'availabilitySetName'

    expect(outputs.size).to eq(2)
    expect(outputs.first).to have_attributes(
      :key         => name,
      :value       => 'miq-availability-set-deployment-eastus',
      :description => name,
      :ems_ref     => "/subscriptions/#{@ems.subscription}/resourceGroups/#{@misc_group}"\
                        "/providers/Microsoft.Resources/deployments/#{@orch_template}/#{name}"
    )
  end

  def assert_specific_orchestration_stack_associations
    child_template_name = 'miq-nested-template'
    child_template = ManageIQ::Providers::Azure::CloudManager::OrchestrationTemplate.find_by(:name => child_template_name)
    child_stack = ManageIQ::Providers::Azure::CloudManager::OrchestrationStack.find_by(:name => child_template.name)

    # orchestration stack belongs to a provider
    expect(child_stack.ext_management_system).to eql(@ems)

    # orchestration stack belongs to an orchestration template
    expect(child_stack.orchestration_template).to eql(child_template)

    # orchestration stack can be nested
    parent_stack = ManageIQ::Providers::Azure::CloudManager::OrchestrationStack.find_by(:name => @orch_template)

    expect(child_stack.parent).to eql(parent_stack)
    expect(parent_stack.children).to include(child_stack)

    # orchestration stack can have cloud networks
    cloud_network = CloudNetwork.find_by(:name => 'miq-vnet-deployment-eastus')
    expect(cloud_network.orchestration_stack).to eql(parent_stack)
  end

  def assert_specific_nic_and_ip
    res_group = 'miq-networking-eastus'
    nic_name  = 'miq-nic-eastus1'
    ip_name   = 'miq-publicip-eastus1'

    ems_ref_nic = "/subscriptions/#{@ems.subscription}/resourceGroups"\
                   "/#{res_group}/providers/Microsoft.Network"\
                   "/networkInterfaces/#{nic_name}"

    ems_ref_ip = "/subscriptions/#{@ems.subscription}/resourceGroups"\
                   "/#{res_group}/providers/Microsoft.Network"\
                   "/publicIPAddresses/#{ip_name}"

    network_port = ManageIQ::Providers::Azure::NetworkManager::NetworkPort.find_by(:ems_ref => ems_ref_nic)
    floating_ip  = ManageIQ::Providers::Azure::NetworkManager::FloatingIp.find_by(:ems_ref => ems_ref_ip)

    expect(network_port).to have_attributes(
      :status  => 'Succeeded',
      :name    => nic_name,
      :ems_ref => ems_ref_nic
    )

    expect(floating_ip).to have_attributes(
      :status  => 'Succeeded',
      :address => @ubuntu_ip_address,
      :ems_ref => ems_ref_ip,
    )

    expect(network_port.device.id).to eql(floating_ip.vm.id)
  end

  def assert_specific_cloud_database
    resource_group = ManageIQ::Providers::Azure::CloudManager::ResourceGroup.find_by(:name => @misc_group)

    sql_cloud_database = ManageIQ::Providers::Azure::CloudManager::CloudDatabase.find_by(
      :ems_ref => "/subscriptions/AZURE_SUBSCRIPTION_ID/resourceGroups/miq-misc-eastus/providers/Microsoft.Sql/servers/db-test/databases/miq-test"
    )

    expect(sql_cloud_database).to have_attributes(
      :ems_ref        => "/subscriptions/AZURE_SUBSCRIPTION_ID/resourceGroups/miq-misc-eastus/providers/Microsoft.Sql/servers/db-test/databases/miq-test",
      :name           => "db-test/miq-test",
      :db_engine      => "SQL Server 12.0",
      :resource_group => resource_group
    )

    pg_cloud_database = ManageIQ::Providers::Azure::CloudManager::CloudDatabase.find_by(
      :ems_ref => "/subscriptions/AZURE_SUBSCRIPTION_ID/resourceGroups/miq-misc-eastus/providers/Microsoft.DBforPostgreSQL/servers/pg-test/databases/postgres"
    )

    expect(pg_cloud_database).to have_attributes(
      :ems_ref        => "/subscriptions/AZURE_SUBSCRIPTION_ID/resourceGroups/miq-misc-eastus/providers/Microsoft.DBforPostgreSQL/servers/pg-test/databases/postgres",
      :name           => "pg-test/postgres",
      :db_engine      => "PostgreSQL 11",
      :status         => "Ready",
      :resource_group => resource_group
    )
  end

  def assert_lbs_with_vms
    assert_specific_load_balancers
    assert_specific_load_balancer_networking
    assert_specific_load_balancer_listeners
    assert_specific_load_balancer_health_checks

    assert_counts(
      :availability_zone                 => 1,
      :cloud_network                     => 1,
      :cloud_subnet                      => 1,
      :disk                              => 2,
      :ext_management_system             => 2,
      :flavor                            => 1,
      :floating_ip                       => 2,
      :hardware                          => 2,
      :load_balancer                     => 2,
      :load_balancer_health_check        => 3,
      :load_balancer_health_check_member => 2,
      :load_balancer_listener            => 1,
      :load_balancer_listener_pool       => 1,
      :load_balancer_pool                => 1,
      :load_balancer_pool_member         => 2,
      :load_balancer_pool_member_pool    => 2,
      :network                           => 2,
      :network_port                      => 4,
      :operating_system                  => 2,
      :resource_group                    => 1,
      :security_group                    => 1,
      :vm                                => 2,
      :vm_or_template                    => 2
    )
  end

  def assert_stack_and_vm_targeted_refresh
    assert_specific_orchestration_template
    assert_specific_orchestration_stack

    assert_counts(
      :availability_zone                 => 0,
      :cloud_network                     => 1,
      :cloud_subnet                      => 1,
      :disk                              => 0,
      :ext_management_system             => 2,
      :flavor                            => 0,
      :floating_ip                       => 0,
      :hardware                          => 0,
      :load_balancer                     => 0,
      :load_balancer_health_check        => 0,
      :load_balancer_health_check_member => 0,
      :load_balancer_listener            => 0,
      :load_balancer_listener_pool       => 0,
      :load_balancer_pool                => 0,
      :load_balancer_pool_member         => 0,
      :load_balancer_pool_member_pool    => 0,
      :network                           => 0,
      :network_port                      => 0,
      :operating_system                  => 0,
      :orchestration_stack               => 2,
      :orchestration_stack_output        => 2,
      :orchestration_stack_parameter     => 5,
      :orchestration_stack_resource      => 5,
      :orchestration_template            => 2,
      :resource_group                    => 1,
      :vm                                => 0,
      :vm_or_template                    => 0
    )
  end

  def network_port_target
    network_port_id = "/subscriptions/#{@ems.subscription}/resourceGroups/#{@network_group}/providers/Microsoft.Network/networkInterfaces/#{@network_interface}"
    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :network_ports,
                                 :manager_ref => {:ems_ref => network_port_id})
  end

  def non_existent_network_port_target
    network_port_id = "/subscriptions/#{@ems.subscription}/resourceGroups/#{@network_group}/providers/Microsoft.Network/networkInterfaces/non_existent"
    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :network_ports,
                                 :manager_ref => {:ems_ref => network_port_id})
  end

  def cloud_network_target
    cloud_network_id = "/subscriptions/#{@ems.subscription}/resourceGroups/#{@network_group}/providers/Microsoft.Network/virtualNetworks/#{@cloud_network}"
    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :cloud_networks,
                                 :manager_ref => {:ems_ref => cloud_network_id})
  end

  def non_existent_cloud_network_target
    cloud_network_id = "/subscriptions/#{@ems.subscription}/resourceGroups/#{@network_group}/providers/Microsoft.Network/virtualNetworks/non_existent"
    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :cloud_networks,
                                 :manager_ref => {:ems_ref => cloud_network_id})
  end

  def security_group_target
    security_group_id = "/subscriptions/#{@ems.subscription}/resourceGroups/#{@network_group}/providers/Microsoft.Network/networkSecurityGroups/#{@security_group}"
    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :security_groups,
                                 :manager_ref => {:ems_ref => security_group_id})
  end

  def non_existent_security_group_target
    security_group_id = "/subscriptions/#{@ems.subscription}/resourceGroups/#{@network_group}/providers/Microsoft.Network/networkSecurityGroups/non_existent"
    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :security_groups,
                                 :manager_ref => {:ems_ref => security_group_id})
  end

  def floating_ip_target
    floating_ip_id = "/subscriptions/#{@ems.subscription}/resourceGroups/#{@network_group}/providers/Microsoft.Network/publicIPAddresses/#{@centos_public_ip}"
    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :floating_ips,
                                 :manager_ref => {:ems_ref => floating_ip_id})
  end

  def non_existent_floating_ip_target
    floating_ip_id = "/subscriptions/#{@ems.subscription}/resourceGroups/#{@network_group}/providers/Microsoft.Network/publicIPAddresses/non_existent"
    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :floating_ips,
                                 :manager_ref => {:ems_ref => floating_ip_id})
  end

  def resource_group_target
    resource_group_id = "/subscriptions/#{@ems.subscription}/resourcegroups/#{@vm_group}"
    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :resource_groups,
                                 :manager_ref => {:ems_ref => resource_group_id})
  end

  def non_existent_resource_group_target
    resource_group_id = "/subscriptions/#{@ems.subscription}/resourcegroups/non_existent"
    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :resource_groups,
                                 :manager_ref => {:ems_ref => resource_group_id})
  end

  def lb_non_stack_target
    lb_resource_id = "/subscriptions/#{@ems.subscription}/"\
                            "resourceGroups/#{@network_group}/providers/Microsoft.Network/loadBalancers/#{@load_balancer}"
    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :load_balancers,
                                 :manager_ref => {:ems_ref => lb_resource_id})
  end

  def lb_non_stack_target2
    lb_resource_id2 = "/subscriptions/#{@ems.subscription}/"\
                            "resourceGroups/#{@network_group}/providers/Microsoft.Network/loadBalancers/miq-lb-eastus2"
    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :load_balancers,
                                 :manager_ref => {:ems_ref => lb_resource_id2})
  end

  def lbs_targets
    [lb_non_stack_target, lb_non_stack_target2]
  end

  def lbs_vms_targets
    vm_resource_id1 = "#{@ems.subscription}/#{@vm_group}/microsoft.compute/virtualmachines/miq-vm1-lb-eastus"
    vm_target1      = InventoryRefresh::Target.new(:manager     => @ems,
                                                   :association => :vms,
                                                   :manager_ref => {:ems_ref => vm_resource_id1})

    vm_resource_id2 = "#{@ems.subscription}/#{@vm_group}/microsoft.compute/virtualmachines/miq-vm2-lb-eastus"
    vm_target2      = InventoryRefresh::Target.new(:manager     => @ems,
                                                   :association => :vms,
                                                   :manager_ref => {:ems_ref => vm_resource_id2})
    [vm_target1, vm_target2]
  end

  def vm_powered_on_target
    vm_resource_id = "#{@ems.subscription}/#{@vm_group}/microsoft.compute/virtualmachines/#{@vm_powered_on}"

    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :vms,
                                 :manager_ref => {:ems_ref => vm_resource_id})
  end

  def vm_in_other_region
    vm_resource_id = "#{@ems.subscription}/#{@vm_group}2/microsoft.compute/virtualmachines/#{@vm_in_other_region}"

    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :vms,
                                 :manager_ref => {:ems_ref => vm_resource_id})
  end

  def vm_powered_off_target
    vm_resource_id = "#{@ems.subscription}/#{@vm_group}/microsoft.compute/virtualmachines/#{@vm_powered_off}"

    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :vms,
                                 :manager_ref => {:ems_ref => vm_resource_id})
  end

  def vm_with_managed_disk_target
    vm_resource_id = "#{@ems.subscription}/#{@vm_group}/microsoft.compute/virtualmachines/#{@managed_vm}"

    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :vms,
                                 :manager_ref => {:ems_ref => vm_resource_id})
  end

  def non_existent_vm_target
    vm_resource_id = "#{@ems.subscription}/#{@vm_group}/microsoft.compute/virtualmachines/non_existent_vm_that_does_not_exist"

    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :vms,
                                 :manager_ref => {:ems_ref => vm_resource_id})
  end

  def parent_orchestration_stack_target
    stack_resource_id = "/subscriptions/#{@ems.subscription}/resourceGroups/#{@misc_group}"\
                          "/providers/Microsoft.Resources/deployments/#{@orch_template}"

    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :orchestration_stacks,
                                 :manager_ref => {:ems_ref => stack_resource_id})
  end

  def non_existent_orchestration_stack_target
    stack_resource_id = "/subscriptions/#{@ems.subscription}/resourceGroups/#{@misc_group}"\
                          "/providers/Microsoft.Resources/deployments/non_existent"

    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :orchestration_stacks,
                                 :manager_ref => {:ems_ref => stack_resource_id})
  end

  def child_orchestration_stack_vm_target
    vm_resource_id = "#{@ems.subscription}/#{@vm_group}/microsoft.compute/virtualmachines/miq-vm1-lb-eastus"
    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :vms,
                                 :manager_ref => {:ems_ref => vm_resource_id})
  end

  def child_orchestration_stack_vm_target2
    vm_resource_id2 = "#{@ems.subscription}/#{@vm_group}/microsoft.compute/virtualmachines/miq-vm2-lb-eastus"
    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :vms,
                                 :manager_ref => {:ems_ref => vm_resource_id2})
  end

  def lb_target
    lb_resource_id = "/subscriptions/#{@ems.subscription}/resourceGroups/#{@network_group}"\
                       "/providers/Microsoft.Network/loadBalancers/#{@load_balancer}"

    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :load_balancers,
                                 :manager_ref => {:ems_ref => lb_resource_id})
  end

  def non_existent_lb_target
    lb_resource_id = "/subscriptions/#{@ems.subscription}/resourceGroups/#{@network_group}"\
                       "/providers/Microsoft.Network/loadBalancers/non_existent_lb"

    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :load_balancers,
                                 :manager_ref => {:ems_ref => lb_resource_id})
  end

  def template_target
    template_resource_id = "/subscriptions/#{@ems.subscription}/resourcegroups/#{@vm_group}"\
                             "/providers/microsoft.compute/images/#{@image_name}"

    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :miq_templates,
                                 :manager_ref => {:ems_ref => template_resource_id})
  end

  def non_existent_template_target
    template_resource_id = "/subscriptions/#{@ems.subscription}/resourcegroups/#{@vm_group}"\
                             "/providers/microsoft.compute/images/non_existent_template"

    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :miq_templates,
                                 :manager_ref => {:ems_ref => template_resource_id})
  end

  def flavor_target
    flavor_resource_id = "basic_a0"
    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :flavors,
                                 :manager_ref => {:ems_ref => flavor_resource_id})
  end

  def non_existent_flavor_target
    flavor_resource_id = "non_existent"
    InventoryRefresh::Target.new(:manager     => @ems,
                                 :association => :flavors,
                                 :manager_ref => {:ems_ref => flavor_resource_id})
  end
end
