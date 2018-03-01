require 'azure-armrest'
require_relative 'azure_refresher_spec_common'

describe ManageIQ::Providers::Azure::CloudManager::Refresher do
  include AzureRefresherSpecCommon

  AzureRefresherSpecCommon::ALL_REFRESH_SETTINGS.each do |refresh_settings|
    context "with settings #{refresh_settings}" do
      before do
        _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone

        @ems = FactoryGirl.create(:ems_azure_with_vcr_authentication, :zone => zone, :provider_region => 'eastus')

        @resource_group    = 'miq-azure-test1'
        @managed_vm        = 'miqazure-linux-managed'
        @device_name       = 'miq-test-rhel1' # Make sure this is running if generating a new cassette.
        @ip_address        = '52.224.165.15'  # This will change if you had to restart the @device_name.
        @mismatch_ip       = '52.168.33.118'  # This will change if you had to restart the 'miqmismatch1' VM.
        @managed_os_disk   = "miqazure-linux-managed_OsDisk_1_7b2bdf790a7d4379ace2846d307730cd"
        @managed_data_disk = "miqazure-linux-managed-data-disk"
        @template          = nil
        @avail_zone        = nil
      end

      after do
        ::Azure::Armrest::Configuration.clear_caches
      end

      AzureRefresherSpecCommon::ALL_REFRESH_SETTINGS.each do |prev_refresh_settings|
        it "is consistent when preceded by refresh settings #{prev_refresh_settings}" do
          setup_ems_and_cassette(prev_refresh_settings)
          inventory_before = serialize_inventory
          setup_ems_and_cassette(refresh_settings)
          inventory_after = serialize_inventory

          aggregate_failures do
            AzureRefresherSpecCommon::MODELS.each do |model|
              expect(inventory_after[model].count).to eq inventory_before[model].count

              inventory_after[model].each do |item_after|
                item_before = inventory_before[model].detect { |i| i["id"] == item_after["id"] }
                expect(item_after).to eq(item_before), \
                  "class: #{model.to_s.classify}\nexpected: #{item_before}\ngot: #{item_after}"
              end
            end
          end
        end
      end
    end
  end
end
