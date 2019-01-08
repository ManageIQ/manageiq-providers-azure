class ManageIQ::Providers::Azure::NetworkManager::FloatingIp < ::FloatingIp
  def self.available
    joins(:network_port).where("network_ports.device_id" => nil) + where(:network_port_id => nil)
  end

  def self.display_name(number = 1)
    n_('Floating IP (Microsoft Azure)', 'Floating IPs (Microsoft Azure)', number)
  end
end
