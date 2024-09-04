module ManageIQ::Providers::Azure::CloudManager::Provision::StateMachine
  def customize_destination
    message = "Customizing #{for_destination}"
    _log.info("#{message} #{for_destination}")
    update_and_notify_parent(:message => message)

    signal :post_create_destination
  end

  def clone_failure_cleanup
    return if phase_context[:clone_options].nil?
    
    delete_instance(phase_context[:clone_options]) if phase_context[:clone_options]
    signal :provision_error
  rescue Azure::Armrest::BadRequestException
    requeue_phase(3.minutes)
  end

  def delete_instance(instance_attrs)
    source.with_provider_connection do |azure|
      nis = ::Azure::Armrest::Network::NetworkInterfaceService.new(azure)
      ips = ::Azure::Armrest::Network::IpAddressService.new(azure)
      ni = nis.get(instance_attrs[:name], resource_group.name)
      ip = ips.get("#{instance_attrs[:name]}-publicIp", resource_group.name)
      nis.delete(instance_attrs[:name], resource_group.name) if ni
      ips.delete("#{instance_attrs[:name]}-publicIp", resource_group.name) if ip
    end
  end
end
