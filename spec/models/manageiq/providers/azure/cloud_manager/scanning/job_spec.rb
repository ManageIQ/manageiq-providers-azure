describe ManageIQ::Providers::Azure::CloudManager::Scanning::Job do
  let(:user)    { FactoryBot.create(:user_with_group) }
  let(:tenant)  { FactoryBot.create(:tenant) }
  let(:ems)     { FactoryBot.create(:ems_azure, :tenant => tenant) }
  let(:vm)      { FactoryBot.create(:vm_azure, :ext_management_system => ems, :evm_owner => user, :miq_group => user.current_group) }
  let!(:server) { EvmSpecHelper.local_miq_server(:vm => vm) }

  before { allow(MiqEventDefinition).to receive_messages(:find_by => true) }

  context "#scan" do
    before do
      vm.scan
      job_item = MiqQueue.find_by(:class_name => "MiqAeEngine", :method_name => "deliver")
      job_item.delivered(*job_item.deliver)
    end

    let(:job) { described_class.first }

    it "should start in state waiting_to_start" do
      expect(job.state).to eq("waiting_to_start")
    end

    it "should start in a dispatch_status of pending" do
      expect(job.dispatch_status).to eq("pending")
    end

    context "#start" do
      it "should raise vm_scan_start for Vm" do
        expect(MiqAeEvent).to receive(:raise_evm_event).with(
          "vm_scan_start",
          an_instance_of(ManageIQ::Providers::Azure::CloudManager::Vm),
          an_instance_of(Hash),
          an_instance_of(Hash)
        )
        job.start
      end

      it "queues before_scan" do
        job.start
        job_item = MiqQueue.find_by(:class_name => "MiqAeEngine", :method_name => "deliver")
        job_item.delivered(*job_item.deliver)
        expect(MiqQueue.last.method_name).to eq("signal")
      end
    end

    describe "#call_scan" do
      before do
        job.miq_server_id = server.id
        allow(VmOrTemplate).to receive(:find).with(vm.id).and_return(vm)
        allow(MiqServer).to receive(:find).with(server.id).and_return(server)
      end

      it "calls #scan_metadata on target VM and as result " do
        expect(vm).to receive(:scan_metadata)
        job.call_scan
      end

      it "triggers adding MiqServer#scan_metada to MiqQueue" do
        job.call_scan
        queue_item = MiqQueue.where(:class_name => "MiqServer", :queue_name => "smartproxy").first
        expect(server.id).to eq queue_item.instance_id
        expect(queue_item.args[0].vm_guid).to eq vm.guid
      end

      it "updates job message" do
        allow(vm).to receive(:scan_metadata)
        job.call_scan
        expect(job.message).to eq "Scanning for metadata from VM"
      end

      it "sends signal :abort if there is any error" do
        allow(vm).to receive(:scan_metadata).and_raise("Any Error")
        expect(job).to receive(:signal).with(:abort, any_args)
        job.call_scan
      end
    end

    describe "#call_synchronize" do
      before do
        job.miq_server_id = server.id
        allow(VmOrTemplate).to receive(:find).with(vm.id).and_return(vm)
        allow(MiqServer).to receive(:find).with(server.id).and_return(server)
      end

      it "calls VmOrTemlate#sync_metadata with correct parameters" do
        expect(vm).to receive(:sync_metadata).with(any_args, "taskid" => job.jobid, "host" => server)
        job.call_synchronize
      end

      it "sends signal :abort if there is any error" do
        allow(vm).to receive(:sync_metadata).and_raise("Any Error")
        expect(job).to receive(:signal).with(:abort, any_args)
        job.call_synchronize
      end

      it "does not updates job status" do
        expect(job).to receive(:set_status).with("Synchronizing metadata from VM")
        job.call_synchronize
      end

      it "executes Job#dispatch_finish" do
        expect(job).to receive(:dispatch_finish)
        job.call_synchronize
      end
    end
  end
end
