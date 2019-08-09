describe ManageIQ::Providers::Azure::CloudManager::EventParser do
  let(:vm_with_description) do
    ManageIQ::Providers::Azure::Engine.root.join('spec/fixtures/events/vm_with_description.json')
  end

  let(:vm_no_description) do
    ManageIQ::Providers::Azure::Engine.root.join('spec/fixtures/events/vm_no_description.json')
  end

  let(:storage_account) do
    ManageIQ::Providers::Azure::Engine.root.join('spec/fixtures/events/storage_account.json')
  end

  context 'event_to_hash' do
    it 'parses vm information with description into event' do
      event = JSON.parse(File.read(vm_with_description))
      hash = described_class.event_to_hash(event, nil)

      expect(hash).to include(
        :source     => 'AZURE',
        :timestamp  => '2017-11-21T19:47:07.5023866Z',
        :message    => nil,
        :ems_id     => nil,
        :event_type => 'virtualMachines_deallocate_BeginRequest',
        :full_data  => event,
        :vm_ems_ref => "xyz/bar/microsoft.compute/virtualmachines/another_vm",
        :vm_uid_ems => "xyz/bar/microsoft.compute/virtualmachines/another_vm"
      )
    end

    it 'parses vm information with no description into event' do
      event = JSON.parse(File.read(vm_no_description))
      hash = described_class.event_to_hash(event, nil)

      expect(hash).to include(
        :source     => 'AZURE',
        :timestamp  => '2017-11-21T19:44:42.5032036Z',
        :message    => nil,
        :ems_id     => nil,
        :event_type => 'New Recommendation',
        :full_data  => event,
        :vm_ems_ref => "xyz/foo/microsoft.compute/virtualmachines/my_vm1",
        :vm_uid_ems => "xyz/foo/microsoft.compute/virtualmachines/my_vm1"
      )
    end

    it 'parses non-vm information into event' do
      event = JSON.parse(File.read(storage_account))
      hash = described_class.event_to_hash(event, nil)

      expect(hash).to include(
        :source     => 'AZURE',
        :timestamp  => '2017-11-20T08:24:46.8082029Z',
        :message    => nil,
        :ems_id     => nil,
        :event_type => 'storageAccounts_listKeys_BeginRequest',
        :full_data  => event,
      )

      expect(hash.key?(:vm_ems_ref)).to be(false)
      expect(hash.key?(:vm_uid_ems)).to be(false)
    end
  end
end
