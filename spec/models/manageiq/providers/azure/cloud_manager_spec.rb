require 'azure-armrest'
describe ManageIQ::Providers::Azure::CloudManager do
  describe ".raw_connect" do
    it "decrypts passwords" do
      allow(::Azure::Armrest::Configuration).to receive(:new)

      expect(ManageIQ::Password).to receive(:try_decrypt).with("1234567890")
      described_class.raw_connect("klmnopqrst", "1234567890", "abcdefghij", 'subscription', 'proxy_uri')
    end
  end

  it ".ems_type" do
    expect(described_class.ems_type).to eq('azure')
  end

  it ".description" do
    expect(described_class.description).to eq('Azure')
  end

  it ".default_blacklisted_event_names" do
    expect(described_class.default_blacklisted_event_names).to eq(Settings.ems.ems_azure.blacklisted_event_names)
  end

  describe ".params_for_create" do
    it "dynamically adjusts to new regions" do
      r1_data = {
        :name        => "westus",
        :description => _("West US"),
      }
      r1 = {'us-west-1' => r1_data}
      r2_data = {
        :name        => "eastus",
        :description => _("East US"),
      }
      r2 = {'us-east-1' => r2_data}

      expect(ManageIQ::Providers::Azure::Regions).to receive(:regions).and_return({})
      options = DDF.find_field(described_class.params_for_create, "provider_region")[:options]
      expect(options).to be_empty

      expect(ManageIQ::Providers::Azure::Regions).to receive(:regions).and_return(r1)
      options = DDF.find_field(described_class.params_for_create, "provider_region")[:options]
      expect(options).to eq [
        {:label => r1_data[:description], :value => r1_data[:name]}
      ]

      expect(ManageIQ::Providers::Azure::Regions).to receive(:regions).and_return(r1.merge(r2))
      options = DDF.find_field(described_class.params_for_create, "provider_region")[:options]
      expect(options).to eq [
        # Note that this also tests that the providers are returned properly sorted
        {:label => r2_data[:description], :value => r2_data[:name]},
        {:label => r1_data[:description], :value => r1_data[:name]}
      ]
    end
  end

  it "does not create orphaned network_manager" do
    # When the cloud_manager is destroyed during a refresh the there will still be an instance
    # of the cloud_manager in the refresh worker. After the refresh we will try to save the cloud_manager
    # and because the network_manager was added before_validate it would create a new network_manager
    #
    # https://bugzilla.redhat.com/show_bug.cgi?id=1389459
    # https://bugzilla.redhat.com/show_bug.cgi?id=1393675
    ems = FactoryBot.create(:ems_azure)
    same_ems = ExtManagementSystem.find(ems.id)

    ems.destroy
    expect(ExtManagementSystem.count).to eq(0)

    same_ems.save!
    expect(ExtManagementSystem.count).to eq(0)
  end

  it "moves the network_manager to the same zone and provider region as the cloud_manager" do
    zone1 = FactoryBot.create(:zone)
    zone2 = FactoryBot.create(:zone)

    ems = FactoryBot.create(:ems_azure, :zone => zone1, :provider_region => "region1")
    expect(ems.network_manager.zone).to eq zone1
    expect(ems.network_manager.zone_id).to eq zone1.id
    expect(ems.network_manager.provider_region).to eq "region1"

    ems.zone = zone2
    ems.provider_region = "region2"
    ems.save!
    ems.reload

    expect(ems.network_manager.zone).to eq zone2
    expect(ems.network_manager.zone_id).to eq zone2.id
    expect(ems.network_manager.provider_region).to eq "region2"
  end

  context "#connectivity" do
    before do
      @e = FactoryBot.create(:ems_azure)
      @e.authentications << FactoryBot.create(:authentication, :userid => "klmnopqrst", :password => "1234567890")
      @e.azure_tenant_id = "abcdefghij"
    end

    context "#connect " do
      it "defaults" do
        expect(described_class).to receive(:raw_connect) do |clientid, clientkey, azure_tenant_id, subscription|
          expect(clientid).to eq("klmnopqrst")
          expect(clientkey).to eq("1234567890")
          expect(azure_tenant_id).to eq("abcdefghij")
          expect(subscription).to eq("fghij67890")
        end
        @e.subscription = "fghij67890"
        @e.connect
      end

      it "with http_proxy_uri" do
        proxy = 'http://www.foo.bar'
        allow(@e).to receive(:http_proxy_uri).and_return(proxy)

        expect(described_class).to receive(:raw_connect) do |_id, _key, _tenant, _sub, http_proxy_uri|
          expect(http_proxy_uri).to eq(proxy)
        end

        @e.connect
      end

      it "with provider_region" do
        expect(described_class).to receive(:raw_connect) do |_id, _key, _tenant, _sub, _proxy, provider_region|
          expect(provider_region).to eq("westus2")
        end

        @e.provider_region = "westus2"
        @e.connect
      end

      it "with endpoint" do
        endpoint = Endpoint.new(:url => 'http://www.foo.bar', :hostname => 'www.foo.bar', :path => '/')
        allow(@e).to receive(:default_endpoint).and_return(endpoint)

        expect(described_class).to receive(:raw_connect) do |_id, _key, _tenant, _sub, _proxy, _region, default_endpoint|
          expect(default_endpoint.url).to eq('http://www.foo.bar')
          expect(default_endpoint.hostname).to eq('www.foo.bar')
          expect(default_endpoint.path).to eq('/')
        end

        @e.connect
      end

      it "with endpoint and path" do
        endpoint = Endpoint.new(:url => 'http://www.foo.bar/some/path', :hostname => 'www.foo.bar', :path => '/some/path')
        allow(@e).to receive(:default_endpoint).and_return(endpoint)

        expect(described_class).to receive(:raw_connect) do |_id, _key, _tenant, _sub, _proxy, _region, default_endpoint|
          expect(default_endpoint.url).to eq('http://www.foo.bar/some/path')
          expect(default_endpoint.hostname).to eq('www.foo.bar')
          expect(default_endpoint.path).to eq('/some/path')
        end

        @e.connect
      end

      it "without subscription id" do
        expect(described_class).to receive(:raw_connect) do |clientid, clientkey, azure_tenant_id, subscription|
          expect(clientid).to eq("klmnopqrst")
          expect(clientkey).to eq("1234567890")
          expect(azure_tenant_id).to eq("abcdefghij")
          expect(subscription).to eq(nil)
        end
        @e.subscription = nil
        @e.connect
      end

      it "accepts overrides" do
        expect(described_class).to receive(:raw_connect) do |clientid, clientkey|
          expect(clientid).to eq("user")
          expect(clientkey).to eq("pass")
        end
        @e.connect(:user => "user", :pass => "pass")
      end
    end

    context "#validation" do
      before do
        @e.subscription = "not_blank"
      end
      it "handles unknown error" do
        allow(Azure::Armrest::Configuration).to receive(:new).and_raise(StandardError)
        expect { @e.verify_credentials }.to raise_error(StandardError, /Unexpected response returned*/)
      end

      it "handles incorrect password" do
        allow(Azure::Armrest::Configuration).to receive(:new).and_raise(Azure::Armrest::UnauthorizedException.new(nil, nil, nil))
        expect { @e.verify_credentials }.to raise_error(MiqException::MiqInvalidCredentialsError, /Incorrect credentials*/)
      end

      it "handles invalid endpoint" do
        allow(@e).to receive(:default_endpoint).and_return(Endpoint.new(:url => 'https://www.foo.bar', :path => '/'))
        allow(Azure::Armrest::Environment).to receive(:discover).and_raise(SocketError)
        expect { @e.verify_credentials }.to raise_error(MiqException::MiqUnreachableError, /Invalid endpoint*/)
      end
    end
  end

  context ".discover" do
    AZURE_PREFIX = /Azure-(\w+)/

    before do
      EvmSpecHelper.local_miq_server(:zone => Zone.seed)

      @client_id    = Rails.application.secrets.azure.try(:[], :client_id) || 'AZURE_CLIENT_ID'
      @client_key   = Rails.application.secrets.azure.try(:[], :client_secret) || 'AZURE_CLIENT_SECRET'
      @tenant_id    = Rails.application.secrets.azure.try(:[], :tenant_id) || 'AZURE_TENANT_ID'
      @subscription = Rails.application.secrets.azure.try(:[], :subscription_id) || 'AZURE_SUBSCRIPTION_ID'

      @alt_client_id    = 'testuser'
      @alt_client_key   = 'secret'
      @alt_tenant_id    = 'ABCDEFGHIJABCDEFGHIJ0123456789AB'
      @alt_subscription = '0123456789ABCDEFGHIJABCDEFGHIJKL'

      # A true thread may fail the test with VCR
      allow(Thread).to receive(:new) do |*args, &block|
        block.call(*args)
        Class.new do
          def join; end
        end.new
      end
    end

    after do
      ::Azure::Armrest::Configuration.clear_caches
    end

    def recorded_discover(example)
      cassette_name = example.description.tr(" ", "_").delete(",").underscore
      name = "#{described_class.name.underscore}/discover/#{cassette_name}"
      VCR.use_cassette(name, :allow_unused_http_interactions => true, :decode_compressed_response => true) do
        ManageIQ::Providers::Azure::CloudManager.discover(@client_id, @client_key, @tenant_id, @subscription)
      end
    end

    def assert_region(ems, name)
      expect(ems.name).to eq(name)
      expect(ems.provider_region).to eq(name[AZURE_PREFIX, 1])
      expect(ems.auth_user_pwd).to eq([@client_id, @client_key])
      expect(ems.azure_tenant_id).to eq(@tenant_id)
      expect(ems.subscription).to eq(@subscription)
    end

    def assert_region_on_another_account(ems, name)
      expect(ems.name).to eq(name)
      expect(ems.provider_region).to eq(name[AZURE_PREFIX, 1])
      expect(ems.auth_user_pwd).to eq([@alt_client_id, @alt_client_key])
      expect(ems.azure_tenant_id).to eq(@alt_tenant_id)
      expect(ems.subscription).to eq(@alt_subscription)
    end

    def create_factory_ems(name, region)
      ems = FactoryBot.create(:ems_azure, :name => name, :provider_region => region)
      cred = {
        :userid   => @client_id,
        :password => @client_key,
      }
      ems.update(:azure_tenant_id => @tenant_id)
      ems.update(:subscription => @subscription)
      ems.authentications << FactoryBot.create(:authentication, cred)
    end

    it "with no existing records" do |example|
      found = recorded_discover(example)
      expect(found.count).to eq(2)

      emses = ManageIQ::Providers::Azure::CloudManager.order(:name)
      expect(emses.count).to eq(2)
      assert_region(emses[0], "Azure-eastus")
      assert_region(emses[1], "Azure-westus")
    end

    it "with some existing records" do |example|
      create_factory_ems("Azure-eastus", "eastus")

      found = recorded_discover(example)
      expect(found.count).to eq(1)

      emses = ManageIQ::Providers::Azure::CloudManager.order(:name)
      expect(emses.count).to eq(2)
      assert_region(emses[0], "Azure-eastus")
      assert_region(emses[1], "Azure-westus")
    end

    it "with all existing records" do |example|
      create_factory_ems("Azure-eastus", "eastus")
      create_factory_ems("Azure-westus", "westus")

      found = recorded_discover(example)
      expect(found.count).to eq(0)

      emses = ManageIQ::Providers::Azure::CloudManager.order(:name)
      expect(emses.count).to eq(2)
      assert_region(emses[0], "Azure-eastus")
      assert_region(emses[1], "Azure-westus")
    end

    context "supports features" do
      before(:each) do
        name = 'Azure-CentralUS'
        region = 'centralus'
        @ems = FactoryBot.create(:ems_azure, :name => name, :provider_region => region)
      end

      it "supports regions" do
        expect(@ems).to respond_to(:supports_regions?)
        expect(@ems.supports_regions?).to eql(true)
      end

      it "supports_not discovery" do
        expect(@ems).to respond_to(:supports_discovery?)
        expect(@ems.supports_discovery?).to eql(false)
      end

      it "supports provisioning" do
        expect(@ems).to respond_to(:supports_provisioning?)
        expect(@ems.supports_provisioning?).to eql(true)
      end

      it "supports timeline events if insights is registered" do
        allow(@ems).to receive(:insights?).and_return(true)
        expect(@ems).to respond_to(:supports_timeline?)
        expect(@ems.supports_provisioning?).to eql(true)
      end

      it "does not support timeline events if insights not registered" do
        allow(@ems).to receive(:insights?).and_return(false)
        expect(@ems).to respond_to(:supports_timeline?)
        expect(@ems.supports_timeline?).to eql(false)
        expect(@ems.unsupported_reason(:timeline)).to eql('Timeline not supported for this region')
      end
    end

    context "with records from a different account" do
      it "with the same name" do |example|
        FactoryBot.create(:ems_azure_with_authentication, :name => "Azure-westus", :provider_region => "westus")

        found = recorded_discover(example)
        expect(found.count).to eq(2)

        emses = ManageIQ::Providers::Azure::CloudManager.order(:name).includes(:authentications)
        expect(emses.count).to eq(3)
        assert_region(emses[0], "Azure-eastus")
        assert_region_on_another_account(emses[1], "Azure-westus")
        assert_region(emses[2], "Azure-westus #{@client_id}")
      end

      it "with the same name and backup name" do |example|
        FactoryBot.create(
          :ems_azure_with_authentication,
          :name            => "Azure-westus",
          :provider_region => "westus")
        FactoryBot.create(
          :ems_azure_with_authentication,
          :name            => "Azure-westus #{@client_id}",
          :provider_region => "westus")

        found = recorded_discover(example)
        expect(found.count).to eq(2)

        emses = ManageIQ::Providers::Azure::CloudManager.order(:name).includes(:authentications)
        expect(emses.count).to eq(4)

        assert_region(emses[0], "Azure-eastus")
        assert_region_on_another_account(emses[1], "Azure-westus")
        assert_region(emses[2], "Azure-westus 1")
        assert_region_on_another_account(emses[3], "Azure-westus #{@client_id}")
      end

      it "with the same name, backup name, and secondary backup name" do |example|
        FactoryBot.create(:ems_azure_with_authentication, :name => "Azure-westus", :provider_region => "westus")
        FactoryBot.create(
          :ems_azure_with_authentication,
          :name            => "Azure-westus #{@client_id}",
          :provider_region => "westus")
        FactoryBot.create(:ems_azure_with_authentication, :name => "Azure-westus 1", :provider_region => "westus")

        found = recorded_discover(example)
        expect(found.count).to eq(2)

        emses = ManageIQ::Providers::Azure::CloudManager.order(:name).includes(:authentications)
        expect(emses.count).to eq(5)

        assert_region(emses[0], "Azure-eastus")
        assert_region_on_another_account(emses[1], "Azure-westus")
        assert_region_on_another_account(emses[2], "Azure-westus 1")
        assert_region(emses[3], "Azure-westus 2")
        assert_region_on_another_account(emses[4], "Azure-westus #{@client_id}")
      end
    end
  end

  describe "#catalog types" do
    let(:ems) { FactoryBot.create(:ems_azure) }

    it "#catalog_types" do
      expect(ems.catalog_types).to include("azure")
    end
  end
end
