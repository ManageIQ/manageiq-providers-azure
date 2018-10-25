require 'azure-armrest'
require_relative 'azure_refresher_spec_common'

describe ManageIQ::Providers::Azure::CloudManager::Refresher do
  include AzureRefresherSpecCommon

  AzureRefresherSpecCommon::ALL_REFRESH_SETTINGS.each do |refresh_settings|
    context "with settings #{refresh_settings}" do
      before do
        define_shared_variables
        @mismatch_ip = '23.96.82.94'
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

          # assert_models_not_changed(inventory_before, inventory_after)
        end
      end
    end
  end
end
