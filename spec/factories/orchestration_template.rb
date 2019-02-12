FactoryBot.define do
  factory :orchestration_template_azure_in_json,
          :parent => :orchestration_template,
          :class  => "ManageIQ::Providers::Azure::CloudManager::OrchestrationTemplate" do
    content { File.read(ManageIQ::Providers::Azure::Engine.root.join(*%w(spec fixtures orchestration_templates azure_parameters.json))) }
  end
end
