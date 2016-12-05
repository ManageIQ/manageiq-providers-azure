class ManageIQ::Providers::Azure::NetworkManager::FloatingIp < ::FloatingIp
  def self.available
    joins(:network_port).where({ "network_ports.device_id" => nil })
  end
end
