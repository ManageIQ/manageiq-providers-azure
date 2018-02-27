class ManageIQ::Providers::Azure::Inventory::Collector::CloudManager < ManageIQ::Providers::Azure::Inventory::Collector
  def initialize(_manager, _target)
    super

    @nis  = network_interface_service(@config)
    @ips  = ip_address_service(@config)
    @vmm  = virtual_machine_service(@config)
    @asm  = availability_set_service(@config)
    @tds  = template_deployment_service(@config)
    @rgs  = resource_group_service(@config)
    @sas  = storage_account_service(@config)
    @sds  = storage_disk_service(@config)
    @mis  = managed_image_service(@config)
    @vmis = virtual_machine_image_service(@config, :location => manager.provider_region)
  end

  def resource_groups
    collect_inventory(:resource_groups) { @resource_groups ||= @rgs.list(:all => true) }
  end

  def flavors
    collect_inventory(:series) do
      begin
        @vmm.series(@ems.provider_region)
      rescue ::Azure::Armrest::BadGatewayException, ::Azure::Armrest::GatewayTimeoutException,
        ::Azure::Armrest::BadRequestException => err
        _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
        []
      end
    end
  end

  def availability_zones
    collect_inventory(:availability_zones) { [::Azure::Armrest::BaseModel.new(:name => @ems.name, :id => 'default')] }
  end

  def stacks
    stacks = collect_inventory(:deployments) { gather_data_for_this_region(@tds, 'list') }

    stacks.each do |deployment|
      stack_template_hash(deployment)
    end

    stacks
  end

  def stack_templates
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

  def instances
    collect_inventory(:instances) { gather_data_for_this_region(@vmm) }
  end

  # The underlying method that gathers these images is a bit brittle.
  # Consequently, if it raises an error we just log it and move on so
  # that it doesn't affect the rest of inventory collection.
  #
  def images
    collect_inventory(:private_images) { gather_data_for_this_region(@sas, 'list_all_private_images') }
  rescue ::Azure::Armrest::ApiException => err
    _log.warn("Unable to collect Azure private images for: [#{@ems.name}] - [#{@ems.id}]: #{err.message}")
    []
  end

  def managed_images
    collect_inventory(:managed_images) { gather_data_for_this_region(@mis) }
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
      gather_data_for_this_region(@vmis)
    end
  end
end
