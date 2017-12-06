require 'azure-armrest'
describe ManageIQ::Providers::Azure::CloudManager do
  describe ".raw_connect" do
    it "decrypts passwords" do
      allow(::Azure::Armrest::Configuration).to receive(:new)

      expect(MiqPassword).to receive(:try_decrypt).with("1234567890")
      described_class.raw_connect("klmnopqrst", "1234567890", "abcdefghij", 'subscription', 'proxy_uri')
    end
  end

  it ".ems_type" do
    expect(described_class.ems_type).to eq('azure')
  end

  it ".description" do
    expect(described_class.description).to eq('Azure')
  end

  it "does not create orphaned network_manager" do
    # When the cloud_manager is destroyed during a refresh the there will still be an instance
    # of the cloud_manager in the refresh worker. After the refresh we will try to save the cloud_manager
    # and because the network_manager was added before_validate it would create a new network_manager
    #
    # https://bugzilla.redhat.com/show_bug.cgi?id=1389459
    # https://bugzilla.redhat.com/show_bug.cgi?id=1393675
    ems = FactoryGirl.create(:ems_azure)
    same_ems = ExtManagementSystem.find(ems.id)

    ems.destroy
    expect(ExtManagementSystem.count).to eq(0)

    same_ems.save!
    expect(ExtManagementSystem.count).to eq(0)
  end

  it "moves the network_manager to the same zone and provider region as the cloud_manager" do
    zone1 = FactoryGirl.create(:zone)
    zone2 = FactoryGirl.create(:zone)

    ems = FactoryGirl.create(:ems_azure, :zone => zone1, :provider_region => "region1")
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
      @e = FactoryGirl.create(:ems_azure)
      @e.authentications << FactoryGirl.create(:authentication, :userid => "klmnopqrst", :password => "1234567890")
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
        expect { @e.verify_credentials }.to raise_error(MiqException::MiqInvalidCredentialsError, /Unexpected response returned*/)
      end

      it "handles incorrect password" do
        allow(Azure::Armrest::Configuration).to receive(:new).and_raise(Azure::Armrest::UnauthorizedException.new(nil, nil, nil))
        expect { @e.verify_credentials }.to raise_error(MiqException::MiqInvalidCredentialsError, /Incorrect credentials*/)
      end
    end
  end
end
