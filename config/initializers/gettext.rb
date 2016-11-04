Vmdb::Gettext::Domains.add_domain(
  'ManageIQ_Providers_Azure',
  ManageIQ::Providers::Azure::Engine.root.join('locale').to_s,
  :po
)
