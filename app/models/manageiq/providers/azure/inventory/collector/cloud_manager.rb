class ManageIQ::Providers::Azure::Inventory::Collector::CloudManager < ManageIQ::Providers::Azure::Inventory::Collector
  def resource_groups
    @resource_groups ||= collect_inventory(:resource_groups) { @rgs.list(:all => true) }
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

  def instances
    @instances_cache ||= collect_inventory(:instances) { gather_data_for_this_region(@vmm) }

    instances_power_state_advanced_caching(@instances_cache) unless @instances_advanced_caching_done
    @instances_advanced_caching_done = true

    @instances_cache
  end

  # The underlying method that gathers these images is a bit brittle.
  # Consequently, if it raises an error we just log it and move on so
  # that it doesn't affect the rest of inventory collection.
  #
  def images
    collect_inventory(:private_images) { gather_data_for_this_region(@sas, 'list_all_private_images') }
  rescue ::Azure::Armrest::ApiException => err
    _log.warn("Unable to collect Azure private images for: [#{@ems.name}] - [#{@ems.id}]: #{err.message.force_encoding("utf-8")}")
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
