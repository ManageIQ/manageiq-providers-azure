class ManageIQ::Providers::Azure::Inventory::Collector < ManageIQ::Providers::Inventory::Collector
  require_nested :ContainerManager
  require_nested :CloudManager
  require_nested :NetworkManager
  require_nested :TargetCollection

  # TODO: cleanup later when old refresh is deleted
  include ManageIQ::Providers::Azure::RefreshHelperMethods
  include Vmdb::Logging

  attr_reader :subscription_id, :stacks_resources_cache

  def initialize(manager, _target)
    super

    @ems = manager # used in helper methods

    # TODO(lsmola) this takes about 4s, see if we can optimize it
    @config          = manager.connect

    @subscription_id = @config.subscription_id
    @thread_limit    = (options.parallel_thread_limit || 0)
    @record_limit    = (options.targeted_api_collection_threshold || 500).to_i

    @enabled_deployments_caching = options.enabled_deployments_caching.nil? ? true : options.enabled_deployments_caching

    # Caches for optimizing fetching resources and templates of stacks
    @stacks_not_changed_cache = {}
    @stacks_resources_cache = {}
    @stacks_resources_api_cache = {}
    @instances_power_state_cache = {}
    @indexed_instance_account_keys_cache = {}

    @resource_to_stack = {}
    @template_uris     = {} # templates need to be download
    @template_refs     = {} # templates need to be retrieved from VMDB
    @template_directs  = {} # templates contents already got by API

    @nis      = network_interface_service(@config)
    @ips      = ip_address_service(@config)
    @vmm      = virtual_machine_service(@config)
    @asm      = availability_set_service(@config)
    @tds      = template_deployment_service(@config)
    @rgs      = resource_group_service(@config)
    @sas      = storage_account_service(@config)
    @sds      = storage_disk_service(@config)
    @marias   = mariadb_server_service(@config)
    @mariadbs = mariadb_database_service(@config)
    @mysqls   = mysql_server_service(@config)
    @mysqldbs = mysql_database_service(@config)
    @pgs      = postgresql_server_service(@config)
    @pgdbs    = postgresql_db_service(@config)
    @sqls     = sql_server_service(@config)
    @sqldbs   = sql_db_service(@config)
    @mis      = managed_image_service(@config)
    @vmis     = virtual_machine_image_service(@config, :location => @ems.provider_region)
    @vns      = virtual_network_service(@config)
    @nsg      = network_security_group_service(@config)
    @lbs      = load_balancer_service(@config)
    @rts      = route_table_service(@config)
  end

  ##############################################################
  # Shared helpers for full and targeted CloudManager collectors
  ##############################################################
  def managed_disks
    @managed_disks ||= collect_inventory(:managed_disks) { @sds.list_all }
  end

  def storage_accounts
    # We want to always limit storage accounts, to avoid loading all account keys in full refresh. Right now we want to
    # load just used storage accounts.
    return if instances.blank?

    used_storage_accounts = instances.map do |instance|
      disks = instance.properties.storage_profile.data_disks + [instance.properties.storage_profile.os_disk]
      disks.map do |disk|
        next if instance.managed_disk?
        disk_location = disk.try(:vhd).try(:uri)
        if disk_location
          uri = Addressable::URI.parse(disk_location)
          uri.host.split('.').first
        end
      end
    end.flatten.compact.to_set

    @storage_accounts ||= collect_inventory(:storage_accounts) { @sas.list_all }.select do |x|
      used_storage_accounts.include?(x.name)
    end
  end

  def stack_resources(deployment)
    cached_stack_resources = stacks_resources_api_cache[deployment.id]
    return cached_stack_resources if cached_stack_resources

    raw_stack_resources(deployment)
  end

  def power_status(instance)
    cached_power_state = instances_power_state_cache[instance.id]
    return cached_power_state if cached_power_state

    raw_power_status(instance)
  end

  def network_ports
    @network_interfaces ||= collect_inventory(:network_ports) { filter_my_region(@nis.list_all) }
  end

  def network_routers
    @network_routers ||= collect_inventory(:network_routers) { filter_my_region(@rts.list_all) }
  end

  def floating_ips
    @floating_ips ||= collect_inventory(:floating_ips) { filter_my_region(@ips.list_all) }
  end

  def instance_network_ports(instance)
    @indexed_network_ports ||= network_ports.index_by(&:id)

    instance.properties.network_profile.network_interfaces.map { |x| @indexed_network_ports[x.id] }.compact
  end

  def instance_floating_ip(public_ip_obj)
    @indexed_floating_ips ||= floating_ips.index_by(&:id)

    @indexed_floating_ips[public_ip_obj.id]
  end

  def instance_managed_disk(disk_location)
    @indexed_managed_disks ||= managed_disks.index_by { |x| x.id.downcase }

    @indexed_managed_disks[disk_location.downcase]
  end

  def instance_account_keys(storage_acct)
    instance_account_keys_advanced_caching unless @instance_account_keys_advanced_caching_done
    @instance_account_keys_advanced_caching_done = true

    indexed_instance_account_keys_cache[[storage_acct.name, storage_acct.resource_group]]
  end

  def instance_storage_accounts(storage_name)
    @indexes_instance_storage_accounts ||= storage_accounts.index_by { |x| x.name.downcase }

    @indexes_instance_storage_accounts[storage_name.downcase]
  end

  def stacks
    @stacks_cache ||= collect_inventory(:deployments) { stacks_in_parallel(@tds, 'list') }

    stacks_advanced_caching(@stacks_cache) unless @stacks_advanced_caching_done
    @stacks_advanced_caching_done = true

    @stacks_cache
  end

  def stack_templates
    stacks.each do |deployment|
      # Do not fetch templates for stacks we already have in DB and that haven't changed
      next if stacks_not_changed_cache[deployment.id]

      stack_template_hash(deployment)
    end

    # download all template uris
    _log.info("Retrieving templates...")
    @template_uris.each { |uri, template| template[:content] = download_template(uri) }
    _log.info("Retrieving templates...Complete - Count [#{@template_uris.count}]")
    _log.debug("Memory usage: #{'%.02f' % collector_memory_usage} MiB")

    (@template_uris.values + @template_directs.values).select do |raw|
      raw[:content]
    end
  end

  def stack_template_hash(deployment)
    direct_stack_template(deployment) || uri_stack_template(deployment)
  end

  def direct_stack_template(deployment)
    content = @tds.get_template(deployment.name, deployment.resource_group)
    init_template_hash(deployment, content.to_s).tap do |template_hash|
      @template_directs[deployment.id] = template_hash
    end
  rescue ::Azure::Armrest::ConflictException
    # Templates were not saved for deployments created before 03/20/2016
    nil
  end

  def uri_stack_template(deployment)
    uri = deployment.properties.try(:template_link).try(:uri)
    return unless uri
    @template_uris[uri] ||
      init_template_hash(deployment).tap do |template_hash|
        @template_uris[uri] = template_hash
      end
  end

  def init_template_hash(deployment, content = nil)
    # If content is nil it is to be fetched
    ver = deployment.properties.try(:template_link).try(:content_version)
    {
      :description => "contentVersion: #{ver}",
      :name        => deployment.name,
      :uid         => deployment.id,
      :content     => content
    }
  end

  def download_template(uri)
    options = {
      :method      => 'get',
      :url         => uri,
      :proxy       => @config.proxy,
      :ssl_version => @config.ssl_version,
      :ssl_verify  => @config.ssl_verify
    }

    body = RestClient::Request.execute(options).body
    JSON.parse(body).to_s # normalize to remove white spaces
  rescue StandardError => e
    _log.error("Failed to download Azure template #{uri}. Reason: #{e.inspect}")
    nil
  end

  def resource_groups
    @resource_groups ||= collect_inventory(:resource_groups) { @rgs.list(:all => true) }
  end

  def flavors
    @flavors ||= collect_inventory(:series) do
      begin
        @vmm.series(@ems.provider_region)
      rescue ::Azure::Armrest::BadGatewayException, ::Azure::Armrest::GatewayTimeoutException,
             ::Azure::Armrest::BadRequestException => err
        _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
        []
      end
    end
  end

  def flavors_by_name
    @flavors_by_name ||= flavors.index_by(&:name)
  end

  def availability_zones
    collect_inventory(:availability_zones) { [::Azure::Armrest::BaseModel.new(:name => @ems.name, :id => 'default')] }
  end

  def instances
    @instances_cache ||= collect_inventory(:instances) { filter_my_region(@vmm.list_all) }

    instances_power_state_advanced_caching(@instances_cache) unless @instances_advanced_caching_done
    @instances_advanced_caching_done = true

    @instances_cache
  end

  # The underlying method that gathers these images is a bit brittle.
  # Consequently, if it raises an error we just log it and move on so
  # that it doesn't affect the rest of inventory collection.
  #
  def images
    collect_inventory(:private_images) { @sas.list_all_private_images(:location => @ems.provider_region) }
  rescue ::Azure::Armrest::ApiException => err
    _log.warn("Unable to collect Azure private images for: [#{@ems.name}] - [#{@ems.id}]: #{err.message}")
    []
  end

  def managed_images
    collect_inventory(:managed_images) { filter_my_region(@mis.list_all) }
  end

  # Collect marketplace image information if configured to do so. Normally
  # users will specify images in their configuration file. If the option
  # to collect marketplace images is selected, but there are no images
  # specified in the configuration file, it will attempt to collect all
  # marketplace images, which is an expensive operation.
  #
  def market_images
    urns = options.market_image_urns

    if urns
      urns.collect do |urn|
        publisher, offer, sku, version = urn.split(':')

        ::Azure::Armrest::VirtualMachineImage.new(
          :location  => manager.provider_region,
          :publisher => publisher,
          :offer     => offer,
          :sku       => sku,
          :version   => version,
          :id        => urn
        )
      end
    else
      filter_my_region(@vmis.list_all)
    end
  end

  def cloud_networks
    filter_my_region(@vns.list_all)
  end

  def security_groups
    filter_my_region(@nsg.list_all)
  end

  def sql_servers
    @sql_servers ||= @sqls.list_all.select do |server|
      # SqlServer instances have a "user friendly" location name
      # e.g. "US East 2" rather than the more common "useast2" that the
      # `gather_data_for_this_region` method is expecting
      server.location == provider_region_description
    end
  end

  def sql_databases
    @sql_databases ||= sql_servers.flat_map do |sql_server|
      @sqldbs.list_all(sql_server.name, sql_server.resource_group).map { |db| [sql_server, db] }
    end
  end

  def mariadb_servers
    @mariadb_servers ||= filter_my_region(@marias.list_all)
  end

  def mariadb_databases
    @mariadb_databases ||= mariadb_servers.flat_map do |server|
      @mariadbs.list_all(server.name, server.resource_group).map { |db| [server, db] }
    end
  end

  def mysql_servers
    @mysql_servers ||= filter_my_region(@mysqls.list_all)
  end

  def mysql_databases
    @mysql_databases ||= mysql_servers.flat_map do |server|
      @mysqldbs.list_all(server.name, server.resource_group).map { |db| [server, db] }
    end
  end

  def postgresql_servers
    @postgresql_servers ||= filter_my_region(@pgs.list_all)
  end

  def postgresql_databases
    @postgresql_databases ||= postgresql_servers.flat_map do |server|
      @pgdbs.list_all(server.name, server.resource_group).map { |db| [server, db] }
    end
  end

  def load_balancers
    @load_balancers ||= filter_my_region(@lbs.list_all)
  end

  protected

  attr_reader :record_limit, :enabled_deployments_caching
  attr_writer :stacks_resources_cache
  attr_accessor :stacks_not_changed_cache, :stacks_resources_api_cache, :instances_power_state_cache,
                :indexed_instance_account_keys_cache

  # Do not use threads in test environment in order to avoid breaking specs.
  #
  # @return [Integer] Number of threads we will use for API collections
  def thread_limit
    Rails.env.test? ? 0 : @thread_limit
  end

  def stacks_resources_advanced_caching(stacks)
    return if stacks.blank?

    # Fetch resources for stack, but only the stacks that changed
    results = collect_inventory_targeted("stacks_resources") do
      Parallel.map(stacks, :in_threads => thread_limit) do |stack|
        [stack.id, raw_stack_resources(stack)]
      end
    end

    stacks_resources_api_cache.merge!(results.to_h)
  end

  def instances_power_state_advanced_caching(instances)
    return if instances.blank?

    if instances_power_state_cache.blank?
      results = collect_inventory_targeted("instance_power_states") do
        Parallel.map(instances, :in_threads => thread_limit) do |instance|
          [instance.id, raw_power_status(instance)]
        end
      end

      self.instances_power_state_cache = results.to_h
    end
  end

  def stacks_advanced_caching(stacks, refs = nil)
    if enabled_deployments_caching
      db_stacks_timestamps              = {}
      db_stacks_primary_keys            = {}
      db_stacks_primary_keys_to_ems_ref = {}

      query = manager.orchestration_stacks
      query = query.where(:ems_ref => refs) if refs

      query.find_each do |stack|
        db_stacks_timestamps[stack.ems_ref]         = stack.finish_time
        db_stacks_primary_keys[stack.ems_ref]       = stack.id
        db_stacks_primary_keys_to_ems_ref[stack.id] = stack.ems_ref
      end

      stacks.each do |deployment|
        next if (api_timestamp = deployment.properties.timestamp).blank?
        next if (db_timestamp = db_stacks_timestamps[deployment.id]).nil?

        api_timestamp = Time.parse(api_timestamp).utc
        db_timestamp = db_timestamp.utc
        # If there isn't a new version of stack, we take times are equal if the difference is below 1s
        next if (db_timestamp < api_timestamp) && ((db_timestamp - api_timestamp).abs > 1.0)

        stacks_not_changed_cache[deployment.id] = db_stacks_primary_keys[deployment.id]
      end

      # Cache resources from the DB
      not_changed_stacks_ids = db_stacks_primary_keys.values
      not_changed_stacks_ids.each_slice(1000) do |batch|
        manager.orchestration_stacks_resources.where(:stack_id => batch).each do |resource|
          ems_ref = db_stacks_primary_keys_to_ems_ref[resource.stack_id]
          next unless ems_ref

          (stacks_resources_cache[ems_ref] ||= []) << parse_db_resource(resource)
        end
      end

      # Cache resources from the API
      stacks_resources_advanced_caching(stacks.reject { |x| stacks_not_changed_cache[x.id] })
    end
  end

  def instance_account_keys_advanced_caching
    return if storage_accounts.blank?

    acc_keys = Parallel.map(storage_accounts, :in_threads => thread_limit) do |storage_acct|
      [
        [storage_acct.name, storage_acct.resource_group],
        collect_inventory(:account_keys) { @sas.list_account_keys(storage_acct.name, storage_acct.resource_group) }
      ]
    end

    indexed_instance_account_keys_cache.merge!(acc_keys.to_h)
  end

  def safe_targeted_request
    yield
  rescue ::Azure::Armrest::Exception => err
    _log.debug("Record not found Error Class=#{err.class.name}, Message=#{err.message}")
    nil
  end

  private

  def raw_stack_resources(deployment)
    group = deployment.resource_group
    name  = deployment.name

    resources = collect_inventory(:stack_resources) { @tds.list_deployment_operations(name, group) }
    # resources with provsioning_operation 'Create' are the ones created by this stack
    resources.select! do |resource|
      resource.properties.provisioning_operation =~ /^create$/i
    end

    resources
  rescue ::Azure::Armrest::Exception => err
    _log.debug("Records not found Error Class=#{err.class.name}, Message=#{err.message}")
    []
  end

  def raw_power_status(instance)
    view   = @vmm.get_instance_view(instance.name, instance.resource_group)
    status = view.statuses.find { |s| s.code =~ %r{^PowerState/} }
    status&.display_status
  rescue ::Azure::Armrest::NotFoundException
    'off' # Possible race condition caused by retirement deletion.
  end

  def parse_db_resource(resource)
    {
      :ems_ref                => resource.ems_ref,
      :name                   => resource.name,
      :logical_resource       => resource.logical_resource,
      :physical_resource      => resource.physical_resource,
      :resource_category      => resource.resource_category,
      :resource_status        => resource.resource_status,
      :resource_status_reason => resource.resource_status_reason,
      :last_updated           => resource.last_updated
    }
  end

  def stacks_in_parallel(arm_service, method_name)
    region = @ems.provider_region

    Parallel.map(resource_groups, :in_threads => thread_limit) do |resource_group|
      arm_service.send(method_name, resource_group.name).select do |resource|
        location = resource.respond_to?(:location) ? resource.location : resource_group.location
        location.casecmp(region).zero?
      end
    end.flatten
  end
end
