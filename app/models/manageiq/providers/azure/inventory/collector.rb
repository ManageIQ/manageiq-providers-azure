class ManageIQ::Providers::Azure::Inventory::Collector < ManagerRefresh::Inventory::Collector
  require_nested :CloudManager
  require_nested :NetworkManager
  require_nested :TargetCollection

  attr_reader :subscription_id

  # TODO: cleanup later when old refresh is deleted
  include ManageIQ::Providers::Azure::RefreshHelperMethods
  include Vmdb::Logging

  def initialize(manager, _target)
    super

    @ems = manager # used in helper methods

    @config          = manager.connect
    @subscription_id = @config.subscription_id
    @thread_limit    = Settings.ems_refresh.azure.parallel_thread_limit

    @resource_to_stack = {}
    @template_uris     = {} # templates need to be download
    @template_refs     = {} # templates need to be retrieved from VMDB
    @template_directs  = {} # templates contents already got by API
  end

  ##############################################################
  # Shared helpers for full and targeted CloudManager collectors
  ##############################################################
  def managed_disks
    @managed_disks ||= @sds.list_all
  end

  def storage_accounts
    @storage_accounts ||= @sas.list_all
  end

  def stack_resources(deployment)
    group = deployment.resource_group
    name  = deployment.name

    resources = collect_inventory(:stack_resources) { @tds.list_deployment_operations(name, group) }
    # resources with provsioning_operation 'Create' are the ones created by this stack
    resources.select! do |resource|
      resource.properties.provisioning_operation =~ /^create$/i
    end

    resources
  end

  def power_status(instance)
    view = @vmm.get_instance_view(instance.name, instance.resource_group)
    status = view.statuses.find { |s| s.code =~ %r{^PowerState/} }
    status&.display_status
  rescue ::Azure::Armrest::NotFoundException
    'off' # Possible race condition caused by retirement deletion.
  end

  def account_keys(storage_acct)
    @sas.list_account_keys(storage_acct.name, storage_acct.resource_group)
  end

  def stack_templates
    stacks.each do |deployment|
      stack_template_hash(deployment)
    end

    # download all template uris
    _log.info("Retrieving templates...")
    @template_uris.each { |uri, template| template[:content] = download_template(uri) }
    _log.info("Retrieving templates...Complete - Count [#{@template_uris.count}]")
    _log.debug("Memory usage: #{'%.02f' % collector_memory_usage} MiB")

    # load from existing stacks => templates
    stacks = OrchestrationStack.where(:ems_ref => @template_refs.keys, :ext_management_system => @ems).index_by(&:ems_ref)
    @template_refs.each do |stack_ref, template|
      template[:content] = stacks[stack_ref].try(:orchestration_template).try(:content)
    end

    (@template_uris.values + @template_refs.values + @template_directs.values).select do |raw|
      raw[:content]
    end
  end

  def stack_template_hash(deployment)
    direct_stack_template(deployment) || uri_stack_template(deployment) || id_stack_template(deployment)
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

  def id_stack_template(deployment)
    init_template_hash(deployment).tap do |template_hash|
      @template_refs[deployment.id] = template_hash
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

  # Do not use threads in test environment in order to avoid breaking specs.
  #
  def thread_limit
    Rails.env.test? ? 0 : @thread_limit
  end

  # The point at which we decide to grab a full listing and filter internally
  # instead of grabbing individual resources via parallel threads.
  #
  # The default is to resort to a single request for sets of 500 or less.
  #
  def record_limit(multiplier = 20)
    @thread_limit * multiplier
  end
end
