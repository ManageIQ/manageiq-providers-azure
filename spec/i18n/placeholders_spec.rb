describe :placeholders do
  include_examples :placeholders, ManageIQ::Providers::Azure::Engine.root.join('locale').to_s
end
