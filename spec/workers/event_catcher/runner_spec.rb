RSpec.describe ManageIQ::Providers::Azure::ContainerManager::EventCatcher::Runner do
  describe '#worker_cmdline' do
    let(:runner) { described_class.allocate }

    it 'points at the Kubernetes engine worker binary' do
      expect(runner.send(:worker_cmdline)).to eq(
        ManageIQ::Providers::Kubernetes::Engine.root.join("workers/event_catcher/worker").to_s
      )
    end

    it 'resolves to an existing file' do
      expect(File.exist?(runner.send(:worker_cmdline))).to be(true)
    end
  end
end
