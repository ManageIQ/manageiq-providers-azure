class ManageIQ::Providers::Azure::NetworkManager < ManageIQ::Providers::NetworkManager
  include ManageIQ::Providers::Azure::ManagerMixin

  has_many :floating_ips, :foreign_key => :ems_id, :dependent => :destroy,
           :class_name => "ManageIQ::Providers::Azure::NetworkManager::FloatingIp"

  # Auth and endpoints delegations, editing of this type of manager must be disabled
  delegate :authentication_check,
           :authentication_status,
           :authentication_status_ok?,
           :authentications,
           :authentication_for_summary,
           :zone,
           :connect,
           :verify_credentials,
           :with_provider_connection,
           :address,
           :ip_address,
           :hostname,
           :default_endpoint,
           :endpoints,
           :azure_tenant_id,
           :refresh_ems,
           :refresh,
           :to        => :parent_manager,
           :allow_nil => true

  class << self
    delegate :refresh_ems, :to => ManageIQ::Providers::Azure::CloudManager
  end

  def self.ems_type
    @ems_type ||= "azure_network".freeze
  end

  def self.description
    @description ||= "Azure Network".freeze
  end

  def self.hostname_required?
    false
  end

  def description
    ManageIQ::Providers::Azure::Regions.regions.dig(provider_region, :description)
  end

  def allow_targeted_refresh?
    true
  end

  def self.display_name(number = 1)
    n_('Network Manager (Microsoft Azure)', 'Network Managers (Microsoft Azure)', number)
  end
end
