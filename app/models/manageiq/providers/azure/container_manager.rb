ManageIQ::Providers::Kubernetes::ContainerManager.include(ActsAsStiLeafClass)

class ManageIQ::Providers::Azure::ContainerManager < ManageIQ::Providers::Kubernetes::ContainerManager
  require_nested :Container
  require_nested :ContainerGroup
  require_nested :ContainerNode
  require_nested :EventCatcher
  require_nested :EventParser
  require_nested :Refresher
  require_nested :RefreshWorker

  class << self
    def ems_type
      @ems_type ||= "aks".freeze
    end

    def description
      @description ||= "Azure Kubernetes Service".freeze
    end

    def display_name(number = 1)
      n_('Container Provider (Azure)', 'Container Providers (Azure)', number)
    end

    def default_port
      443
    end

    def azure_token_credentials(tenant_id, client_id, client_secret)
      require "ms_rest_azure"
      MsRest::TokenCredentials.new(
        MsRestAzure::ApplicationTokenProvider.new(tenant_id, client_id, client_secret)
      )
    end

    def aks_cluster_admin_token(credentials, subscription, resource_group, cluster_name)
      kubeconfig = cluster_admin_kubeconfig(credentials, subscription, resource_group, cluster_name)

      user = kubeconfig["users"].first
      user&.dig("user", "token")
    end

    def aks_cluster_uri(credentials, subscription, resource_group, cluster_name)
      kubeconfig = cluster_admin_kubeconfig(credentials, subscription, resource_group, cluster_name)

      cluster_config = kubeconfig["clusters"].detect { |cluster| cluster["name"] == cluster_name }
      cluster_config.dig("cluster", "server")
    end

    def params_for_create
      {
        :fields => [
          {
            :component => 'sub-form',
            :id        => 'endpoints-subform',
            :name      => 'endpoints-subform',
            :title     => _('Endpoints'),
            :fields    => [
              :component => 'tabs',
              :name      => 'tabs',
              :fields    => [
                {
                  :component => 'tab-item',
                  :id        => 'default-tab',
                  :name      => 'default-tab',
                  :title     => _('Default'),
                  :fields    => [
                    {
                      :component              => 'validate-provider-credentials',
                      :id                     => 'authentications.default.valid',
                      :name                   => 'authentications.default.valid',
                      :skipSubmit             => true,
                      :isRequired             => true,
                      :validationDependencies => %w[type],
                      :fields                 => [
                        {
                          :component    => "select",
                          :id           => "endpoints.default.security_protocol",
                          :name         => "endpoints.default.security_protocol",
                          :label        => _("Security Protocol"),
                          :isRequired   => true,
                          :validate     => [{:type => "required"}],
                          :initialValue => 'ssl-with-validation',
                          :options      => [
                            {
                              :label => _("SSL"),
                              :value => "ssl-with-validation"
                            },
                            {
                              :label => _("SSL trusting custom CA"),
                              :value => "ssl-with-validation-custom-ca"
                            },
                            {
                              :label => _("SSL without validation"),
                              :value => "ssl-without-validation",
                            },
                          ]
                        },
                        {
                          :component  => "text-field",
                          :id         => "endpoints.default.hostname",
                          :name       => "endpoints.default.hostname",
                          :label      => _("Hostname (or IPv4 or IPv6 address)"),
                          :isRequired => true,
                          :validate   => [{:type => "required"}],
                        },
                        {
                          :component    => "text-field",
                          :id           => "endpoints.default.port",
                          :name         => "endpoints.default.port",
                          :label        => _("API Port"),
                          :type         => "number",
                          :initialValue => default_port,
                          :isRequired   => true,
                          :validate     => [{:type => "required"}],
                        },
                        {
                          :component  => "textarea",
                          :id         => "endpoints.default.certificate_authority",
                          :name       => "endpoints.default.certificate_authority",
                          :label      => _("Trusted CA Certificates"),
                          :rows       => 10,
                          :isRequired => true,
                          :validate   => [{:type => "required"}],
                          :condition  => {
                            :when => 'endpoints.default.security_protocol',
                            :is   => 'ssl-with-validation-custom-ca',
                          },
                        },
                        {
                          :component  => "password-field",
                          :id         => "authentications.bearer.auth_key",
                          :name       => "authentications.bearer.auth_key",
                          :label      => "Token",
                          :type       => "password",
                          :isRequired => true,
                          :validate   => [{:type => "required"}],
                        },
                      ]
                    }
                  ]
                },
              ]
            ]
          }
        ]
      }
    end

    private

    def cluster_admin_kubeconfig(credentials, subscription_id, resource_group, cluster_name)
      managed_clusters_client   = managed_clusters_client(credentials, subscription_id)
      cluster_admin_credentials = managed_clusters_client.list_cluster_admin_credentials(resource_group, cluster_name)

      YAML.safe_load(cluster_admin_credentials.kubeconfigs.first.value.pack("c*"))
    end

    def managed_clusters_client(credentials, subscription_id)
      require "azure_mgmt_container_service"
      container_service_client = Azure::ContainerService::Mgmt::V2020_12_01::ContainerServiceClient.new(credentials)
      container_service_client.subscription_id = subscription_id # TODO: can this be set in the credentials?

      Azure::ContainerService::Mgmt::V2020_12_01::ManagedClusters.new(container_service_client)
    end
  end
end
