class ManageIQ::Providers::Azure::ContainerManager::EventCatcher::Runner < ManageIQ::Providers::BaseManager::EventCatcher::Runner
  include ManageIQ::Providers::Kubernetes::ContainerManager::EventCatcherMixin

  private

  def worker_cmdline
    ManageIQ::Providers::Kubernetes::Engine.root.join("workers/event_catcher/worker").to_s
  end
end
