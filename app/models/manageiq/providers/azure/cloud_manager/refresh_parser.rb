module ManageIQ::Providers
  module Azure
    class CloudManager::RefreshParser < ManageIQ::Providers::CloudManager::RefreshParser
      include ManageIQ::Providers::Azure::RefreshHelperMethods
      include Vmdb::Logging

      TYPE_DEPLOYMENT = "microsoft.resources/deployments".freeze

      def self.ems_inv_to_hashes(ems, options = Config::Options.new)
        new(ems, options).ems_inv_to_hashes
      end

      def initialize(ems, options = Config::Options.new)
        @ems    = ems
        @config = ems.connect
        @subscription_id = ems.subscription

        # TODO(lsmola) NetworkManager, remove network endpoints once this is entirely moved under NetworkManager
        @nis               = network_interface_service(@config)
        @ips               = ip_address_service(@config)
        @vmm               = virtual_machine_service(@config)
        @asm               = availability_set_service(@config)
        @tds               = template_deployment_service(@config)
        @rgs               = resource_group_service(@config)
        @sas               = storage_account_service(@config)
        @sds               = storage_disk_service(@config)
        @mis               = managed_image_service(@config)
        @vmis              = virtual_machine_image_service(@config, :location => @ems.provider_region)
        @options           = options || {}
        @data              = {}
        @data_index        = {}
        @resource_to_stack = {}
        @template_uris     = {} # templates need to be download
        @template_refs     = {} # templates need to be retrieved from VMDB
        @template_directs  = {} # templates contents already got by API
        @tag_mapper        = ContainerLabelTagMapping.mapper
        @data[:tag_mapper] = @tag_mapper
      end

      def ems_inv_to_hashes
        log_header = "Collecting data for EMS : [#{@ems.name}] id: [#{@ems.id}]"

        _log.info("#{log_header}...")
        get_resource_groups
        get_series
        get_managed_disks
        get_unmanaged_storage
        get_availability_zones
        get_stacks
        get_stack_templates
        get_instances
        get_managed_images
        get_images
        get_market_images if @options.get_market_images
        _log.info("#{log_header}...Complete")

        @data
      end

      private

      def get_managed_disks
        @managed_disks ||= @sds.list_all
      end

      def get_unmanaged_storage
        @storage_accounts ||= @sas.list_all
      end

      def get_resource_groups
        groups = collect_inventory(:resource_groups) { resource_groups }
        process_collection(groups, :resource_groups) do |resource_group|
          parse_resource_group(resource_group)
        end
      end

      def get_series
        series = collect_inventory(:series) do
          begin
            @vmm.series(@ems.provider_region)
          rescue ::Azure::Armrest::BadGatewayException, ::Azure::Armrest::GatewayTimeoutException,
                 ::Azure::Armrest::BadRequestException => err
            _log.error("Error Class=#{err.class.name}, Message=#{err.message}")
            []
          end
        end

        process_collection(series, :flavors) { |s| parse_series(s) }
      end

      def get_availability_zones
        # cannot get availability zones from provider; create a default one
        a_zones = collect_inventory(:availability_zones) { [::Azure::Armrest::BaseModel.new(:name => @ems.name, :id => 'default')] }
        process_collection(a_zones, :availability_zones) { |az| parse_az(az) }
      end

      # Deployments are realizations of a template in the Azure provider.
      # They are parsed and converted to stacks in vmdb.
      #
      def get_deployments
        deployments = collect_inventory(:deployments) { gather_data_for_this_region(@tds, 'list') }
        process_collection(deployments, :orchestration_stacks) { |dp| parse_stack(dp) }
      end

      def get_stacks
        get_deployments
        update_nested_stack_relations
      end

      def get_stack_parameters(stack_id, parameters)
        process_collection(parameters, :orchestration_stack_parameters) do |param_key, param_val|
          parse_stack_parameter(param_key, param_val, stack_id)
        end
      end

      def get_stack_outputs(stack_id, outputs)
        process_collection(outputs, :orchestration_stack_outputs) do |output_key, output_val|
          parse_stack_output(output_key, output_val, stack_id)
        end
      end

      def get_stack_resources(name, group)
        resources = collect_inventory(:stack_resources) { @tds.list_deployment_operations(name, group) }
        # resources with provsioning_operation 'Create' are the ones created by this stack
        resources.select! do |resource|
          resource.properties.provisioning_operation =~ /^create$/i
        end

        process_collection(resources, :orchestration_stack_resources) do |resource|
          parse_stack_resource(resource, group)
        end
      end

      def get_resource_status_message(resource)
        return nil unless resource.properties.respond_to?(:status_message)
        if resource.properties.status_message.respond_to?(:error)
          resource.properties.status_message.error.message
        else
          resource.properties.status_message.to_s
        end
      end

      def get_stack_templates
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

        raw_templates = (@template_uris.values + @template_refs.values + @template_directs.values).select do |raw|
          raw[:content]
        end
        process_collection(raw_templates, :orchestration_templates) do |template|
          parse_stack_template(template)
        end

        # link stacks to templates, convert raw_template to template
        Hash(@data_index[:orchestration_stacks]).each_value do |stack|
          raw_template = stack[:orchestration_template]
          stack[:orchestration_template] = @data_index.fetch_path(:orchestration_templates, raw_template[:uid])
        end
      end

      def get_instances
        instances = collect_inventory(:instances) { gather_data_for_this_region(@vmm) }
        process_collection(instances, :vms) { |instance| parse_instance(instance) }
      end

      # The underlying method that gathers these images is a bit brittle.
      # Consequently, if it raises an error we just log it and move on so
      # that it doesn't affect the rest of inventory collection.
      #
      def get_images
        images = collect_inventory(:private_images) { gather_data_for_this_region(@sas, 'list_all_private_images') }
      rescue ::Azure::Armrest::ApiException => err
        _log.warn("Unable to collect Azure private images for: [#{@ems.name}] - [#{@ems.id}]: #{err.message}")
      else
        process_collection(images, :vms) { |image| parse_image(image) }
      end

      def get_managed_images
        images = collect_inventory(:managed_images) { gather_data_for_this_region(@mis) }
        process_collection(images, :vms) { |image| parse_managed_image(image) }
      end

      # Collect marketplace image information if configured to do so. Normally
      # users will specify images in their configuration file. If the option
      # to collect marketplace images is selected, but there are no images
      # specified in the configuration file, it will attempt to collect all
      # marketplace images, which is an expensive operation.
      #
      def get_market_images
        urns = @options.market_image_urns

        if urns
          images = urns.collect do |urn|
            publisher, offer, sku, version = urn.split(':')

            ::Azure::Armrest::VirtualMachineImage.new(
              :location  => @ems.provider_region,
              :publisher => publisher,
              :offer     => offer,
              :sku       => sku,
              :version   => version,
              :id        => urn
            )
          end
        else
          images = gather_data_for_this_region(@vmis)
        end

        process_collection(images, :vms) { |image| parse_market_image(image) }
      end

      def parse_resource_group(resource_group)
        uid = resource_group.id.downcase
        new_result = {
          :type    => 'ManageIQ::Providers::Azure::ResourceGroup',
          :name    => resource_group.name,
          :ems_ref => uid,
        }
        return uid, new_result
      end

      def parse_series(s)
        name = uid = s.name.downcase
        new_result = {
          :type           => "ManageIQ::Providers::Azure::CloudManager::Flavor",
          :ems_ref        => uid,
          :name           => name,
          :cpus           => s.number_of_cores, # where are the virtual CPUs??
          :cpu_cores      => s.number_of_cores,
          :memory         => s.memory_in_mb.megabytes,
          :root_disk_size => s.os_disk_size_in_mb * 1024,
          :swap_disk_size => s.resource_disk_size_in_mb * 1024
        }
        return uid, new_result
      end

      def parse_az(az)
        id = az.id.downcase

        new_result = {
          :type    => "ManageIQ::Providers::Azure::CloudManager::AvailabilityZone",
          :ems_ref => id,
          :name    => az.name,
        }
        return id, new_result
      end

      def parse_instance(instance)
        uid = File.join(
          @subscription_id,
          instance.resource_group.downcase,
          instance.type.downcase,
          instance.name
        )
        series_name = instance.properties.hardware_profile.vm_size.downcase
        series      = @data_index.fetch_path(:flavors, series_name)

        # TODO(lsmola) NetworkManager, storing IP addresses under hardware/network will go away, once all providers are
        # unified under the NetworkManager
        hardware_network_info = get_hardware_network_info(instance)

        rg_ems_ref = get_resource_group_ems_ref(instance)

        labels = parse_labels(instance.try(:tags) || {})

        new_result = {
          :type                => 'ManageIQ::Providers::Azure::CloudManager::Vm',
          :uid_ems             => uid,
          :ems_ref             => uid,
          :name                => instance.name,
          :vendor              => "azure",
          :raw_power_state     => power_status(instance),
          :operating_system    => process_os(instance),
          :flavor              => series,
          :location            => instance.location,
          :orchestration_stack => @data_index.fetch_path(:orchestration_stacks, @resource_to_stack[uid]),
          :availability_zone   => @data_index.fetch_path(:availability_zones, 'default'),
          :resource_group      => @data_index.fetch_path(:resource_groups, rg_ems_ref),
          :labels              => labels,
          :tags                => map_labels('VmAzure', labels),
          :hardware            => {
            :disks    => [], # Filled in later conditionally on flavor
            :networks => hardware_network_info
          },
        }

        populate_hardware_hash_with_disks(new_result[:hardware][:disks], instance)
        populate_hardware_hash_with_series_attributes(new_result[:hardware], instance, series)

        return uid, new_result
      end

      def power_status(instance)
        view = @vmm.get_instance_view(instance.name, instance.resource_group)
        status = view.statuses.find { |s| s.code =~ %r{^PowerState/} }
        status.display_status if status
      rescue ::Azure::Armrest::NotFoundException
        'off' # Possible race condition caused by retirement deletion.
      end

      def process_os(instance)
        {
          :product_name => guest_os(instance)
        }
      end

      # Find both OS and SKU if possible, otherwise just the OS type.
      def guest_os(instance)
        image_reference = instance.properties.storage_profile.try(:image_reference)
        if image_reference && image_reference.try(:offer)
          "#{image_reference.offer} #{image_reference.sku.tr('-', ' ')}"
        else
          instance.properties.storage_profile.os_disk.os_type
        end
      end

      def populate_hardware_hash_with_disks(hardware_disks_array, instance)
        data_disks = instance.properties.storage_profile.data_disks
        data_disks.each do |disk|
          add_instance_disk(hardware_disks_array, instance, disk)
        end
      end

      # TODO(lsmola) NetworkManager, storing IP addresses under hardware/network will go away, once all providers are
      # unified under the NetworkManager
      def get_hardware_network_info(instance)
        networks_array = []

        get_vm_nics(instance).each do |nic_profile|
          nic_profile.properties.ip_configurations.each do |ipconfig|
            hostname = ipconfig.name
            private_ip_addr = ipconfig.properties.try(:private_ip_address)
            if private_ip_addr
              networks_array << {:description => "private", :ipaddress => private_ip_addr, :hostname => hostname}
            end

            public_ip_obj = ipconfig.properties.try(:public_ip_address)
            next unless public_ip_obj

            ip_profile = ip_addresses.find { |ip| ip.id == public_ip_obj.id }
            next unless ip_profile

            public_ip_addr = ip_profile.properties.try(:ip_address)
            networks_array << {:description => "public", :ipaddress => public_ip_addr, :hostname => hostname}
          end
        end

        networks_array
      end

      def populate_hardware_hash_with_series_attributes(hardware_hash, instance, series)
        return if series.nil?
        hardware_hash[:cpu_total_cores] = series[:cpus]
        hardware_hash[:memory_mb]       = series[:memory] / 1.megabyte
        hardware_hash[:disk_capacity]   = series[:root_disk_size] + series[:swap_disk_size]

        disk = instance.properties.storage_profile.os_disk
        add_instance_disk(hardware_hash[:disks], instance, disk)
      end

      # Redefine the inherited method for our purposes
      def add_instance_disk(array, instance, disk)
        if instance.managed_disk?
          disk_type     = 'managed'
          disk_location = disk.managed_disk.id
          managed_disk  = @managed_disks.find { |d| d.id.casecmp(disk_location).zero? }

          if managed_disk
            disk_size = managed_disk.properties.disk_size_gb.gigabytes
            mode      = managed_disk.sku.name
          else
            _log.warn("Unable to find disk information for #{instance.name}/#{instance.resource_group}")
            disk_size = nil
            mode      = nil
          end
        else
          disk_type     = 'unmanaged'
          disk_location = disk.try(:vhd).try(:uri)
          disk_size     = disk.try(:disk_size_gb).try(:gigabytes)

          if disk_location
            uri = Addressable::URI.parse(disk_location)
            storage_name = uri.host.split('.').first
            container_name = File.dirname(uri.path)
            blob_name = uri.basename

            storage_acct = @storage_accounts.find { |s| s.name.casecmp(storage_name).zero? }
            mode = storage_acct.sku.name

            if @options.get_unmanaged_disk_space && disk_size.nil?
              storage_keys = @sas.list_account_keys(storage_acct.name, storage_acct.resource_group)
              storage_key  = storage_keys['key1'] || storage_keys['key2']
              blob_props   = storage_acct.blob_properties(container_name, blob_name, storage_key)
              disk_size    = blob_props.content_length.to_i
            end
          end
        end

        disk_record = {
          :device_type     => 'disk',
          :controller_type => 'azure',
          :device_name     => disk.name,
          :location        => disk_location,
          :size            => disk_size,
          :disk_type       => disk_type,
          :mode            => mode
        }

        array << disk_record
      end

      def parse_stack(deployment)
        name = deployment.name
        uid = File.join(@subscription_id, deployment.resource_group.downcase, TYPE_DEPLOYMENT, name)
        child_stacks, resources = stack_resources(deployment)

        new_result = {
          :type                   => ManageIQ::Providers::Azure::CloudManager::OrchestrationStack.name,
          :ems_ref                => deployment.id,
          :name                   => name,
          :description            => name,
          :status                 => deployment.properties.provisioning_state,
          :children               => child_stacks,
          :resources              => resources,
          :outputs                => stack_outputs(deployment),
          :parameters             => stack_parameters(deployment),
          :resource_group         => deployment.resource_group,
          :orchestration_template => stack_template_hash(deployment)
        }

        return uid, new_result
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
      rescue => e
        _log.error("Failed to download Azure template #{uri}. Reason: #{e.inspect}")
        nil
      end

      def stack_parameters(deployment)
        raw_parameters = deployment.properties.try(:parameters)
        return [] if raw_parameters.blank?

        stack_id = deployment.id
        get_stack_parameters(stack_id, raw_parameters)
        raw_parameters.collect do |param_key, _val|
          @data_index.fetch_path(:orchestration_stack_parameters, File.join(stack_id, param_key))
        end
      end

      def stack_outputs(deployment)
        raw_outputs = deployment.properties.try(:outputs)
        return [] if raw_outputs.blank?

        stack_id = deployment.id
        get_stack_outputs(stack_id, raw_outputs)
        raw_outputs.collect do |output_key, _val|
          @data_index.fetch_path(:orchestration_stack_outputs, File.join(stack_id, output_key))
        end
      end

      def stack_resources(deployment)
        group = deployment.resource_group
        name = deployment.name
        stack_uid = File.join(@subscription_id, group.downcase, TYPE_DEPLOYMENT, name)

        raw_resources = get_stack_resources(name, group)

        child_stacks = []
        resources = raw_resources.collect do |resource|
          resource_type = resource.properties.target_resource.resource_type
          resource_name = resource.properties.target_resource.resource_name
          uid = File.join(@subscription_id, group.downcase, resource_type.downcase, resource_name)
          @resource_to_stack[uid] = stack_uid
          child_stacks << uid if resource_type.downcase == TYPE_DEPLOYMENT
          @data_index.fetch_path(:orchestration_stack_resources, uid)
        end

        return child_stacks, resources
      end

      def parse_stack_template(template)
        new_result = {
          :type        => ManageIQ::Providers::Azure::CloudManager::OrchestrationTemplate.name,
          :name        => template[:name],
          :description => template[:description],
          :content     => template[:content],
          :orderable   => false
        }
        return template[:uid], new_result
      end

      def parse_stack_parameter(param_key, param_obj, stack_id)
        uid = File.join(stack_id, param_key)
        new_result = {
          :ems_ref => uid,
          :name    => param_key,
          :value   => param_obj['value']
        }
        return uid, new_result
      end

      def parse_stack_output(output_key, output_obj, stack_id)
        uid = File.join(stack_id, output_key)
        new_result = {
          :ems_ref     => uid,
          :key         => output_key,
          :value       => output_obj['value'],
          :description => output_key
        }
        return uid, new_result
      end

      def parse_stack_resource(resource, group)
        status_message = get_resource_status_message(resource)
        status_code = resource.properties.try(:status_code)
        new_result = {
          :ems_ref                => resource.properties.target_resource.id,
          :name                   => resource.properties.target_resource.resource_name,
          :logical_resource       => resource.properties.target_resource.resource_name,
          :physical_resource      => resource.properties.tracking_id,
          :resource_category      => resource.properties.target_resource.resource_type,
          :resource_status        => resource.properties.provisioning_state,
          :resource_status_reason => status_message || status_code,
          :last_updated           => resource.properties.timestamp
        }
        uid = File.join(@subscription_id, group.downcase, new_result[:resource_category].downcase, new_result[:name])
        return uid, new_result
      end

      def parse_managed_image(image)
        uid = image.id.downcase

        os = image.properties.storage_profile.try(:os_disk).try(:os_type) || 'unknown'
        rg_ems_ref = get_resource_group_ems_ref(image)

        new_result = {
          :type               => ManageIQ::Providers::Azure::CloudManager::Template.name,
          :uid_ems            => uid,
          :ems_ref            => uid,
          :name               => image.name,
          :description        => "#{image.resource_group}/#{image.name}",
          :location           => @ems.provider_region,
          :vendor             => 'azure',
          :raw_power_state    => 'never',
          :template           => true,
          :publicly_available => false,
          :operating_system   => process_os(image),
          :resource_group     => @data_index.fetch_path(:resource_groups, rg_ems_ref),
          :hardware           => {
            :bitness  => 64,
            :guest_os => OperatingSystem.normalize_os_name(os)
          }
        }

        return uid, new_result
      end

      def parse_market_image(image)
        uid = image.id

        new_result =
          {
            :type               => ManageIQ::Providers::Azure::CloudManager::Template.name,
            :uid_ems            => uid,
            :ems_ref            => uid,
            :name               => "#{image.offer} - #{image.sku} - #{image.version}",
            :description        => "#{image.offer} - #{image.sku} - #{image.version}",
            :location           => @ems.provider_region,
            :vendor             => 'azure',
            :raw_power_state    => 'never',
            :template           => true,
            :publicly_available => true,
            :hardware           => {
              :bitness  => 64,
              :guest_os => 'unknown'
            }
          }

        return uid, new_result
      end

      def parse_image(image)
        uid = image.uri

        new_result = {
          :type               => ManageIQ::Providers::Azure::CloudManager::Template.name,
          :uid_ems            => uid,
          :ems_ref            => uid,
          :name               => build_image_name(image),
          :description        => build_image_description(image),
          :location           => @ems.provider_region,
          :vendor             => "azure",
          :raw_power_state    => "never",
          :template           => true,
          :publicly_available => false,
          :hardware           => {
            :bitness  => 64,
            :guest_os => OperatingSystem.normalize_os_name(image.operating_system)
          }
        }

        return uid, new_result
      end

      def build_image_name(image)
        # Strip the .vhd and Azure GUID extension, but retain path and base name.
        File.join(File.dirname(image.name), File.basename(File.basename(image.name, '.*'), '.*'))
      end

      def build_image_description(image)
        # Description is a concatenation of resource group and storage account
        "#{image.storage_account.resource_group}/#{image.storage_account.name}"
      end

      # Remap from children to parent
      def update_nested_stack_relations
        Array(@data[:orchestration_stacks]).each do |stack|
          stack[:children].each do |child_stack_id|
            child_stack = @data_index.fetch_path(:orchestration_stacks, child_stack_id)
            child_stack[:parent] = stack if child_stack
          end
          stack.delete(:children)
        end
      end

      def parse_labels(tags)
        tags.map do |tag_name, tag_value|
          {
            :name    => tag_name,
            :value   => tag_value,
            :source  => 'azure',
            :section => 'labels',
          }
        end
      end

      delegate :map_labels, :to => :@tag_mapper
    end
  end
end
