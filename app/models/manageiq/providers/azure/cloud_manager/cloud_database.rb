class ManageIQ::Providers::Azure::CloudManager::CloudDatabase < ::CloudDatabase
  supports :create
  supports :delete

  def self.params_for_create(ems)
    {
      :fields => [
        {
          :component  => 'text-field',
          :id         => 'name',
          :name       => 'name',
          :label      => _('Cloud Database Name'),
          :isRequired => true,
          :validate   => [{:type => 'required'}],
        },
        {
          :component    => 'select',
          :id           => 'resource_group',
          :name         => 'resource_group',
          :label        => _('Resource Group'),
          :includeEmpty => true,
          :isRequired   => true,
          :validate     => [{:type => 'required'}],
          :options      => ems.resource_groups.map do |rg|
            {
              :label => rg[:name],
              :value => rg[:name],
            }
          end,
        },
        {
          :component    => 'select',
          :name         => 'database',
          :id           => 'database',
          :label        => _('Database Type'),
          :includeEmpty => true,
          :isRequired   => true,
          :validate     => [{:type => 'required'}],
          :options      => ['MySQL', 'SQL', 'MariaDB', 'PostgreSQL'].map do |db|
            {
              :label => db,
              :value => db,
            }
          end,
        },
        # TODO: Database Server dropdown should be dependent on 'database type' and 'resource group'
        {
          :component    => 'select',
          :name         => 'server',
          :id           => 'server',
          :label        => _('Database Server Name'),
          :includeEmpty => true,
          :isRequired   => true,
          :validate     => [{:type => 'required'}],
          :options      => ems.cloud_database_servers.map do |srv|
            {
              :label => srv.name,
              :value => srv.name,
            }
          end,
        },
      ],
    }
  end

  def self.raw_create_cloud_database(ext_management_system, options)
    case options["database"]
    when 'SQL'
      db_client = ext_management_system.connect(:service => "SqlDatabaseService")
    when 'MySQL'
      db_client = ext_management_system.connect(:service => "MysqlDatabaseService")
    when 'PostgreSQL'
      db_client = ext_management_system.connect(:service => "PostgresqlDatabaseService")
    when 'MariaDB'
      db_client = ext_management_system.connect(:service => "MariadbDatabaseService")
    else
      raise ArgumentError, _("Invalid database type")
    end

    db_client.create(options["server"], options["name"], options["resource_group"], {:location => ext_management_system.provider_region})
  rescue => err
    _log.error("cloud database=[#{options[:name]}], error: #{err}")
    raise
  end

  def raw_delete_cloud_database
    case db_engine
    when /SQL Server/
      ext_management_system.connect(:service => "SqlDatabaseService").delete_by_id(ems_ref)
    when /MariaDB/
      ext_management_system.connect(:service => "MariadbDatabaseService").delete_by_id(ems_ref)
    when /MySQL/
      ext_management_system.connect(:service => "MysqlDatabaseService").delete_by_id(ems_ref)
    when /PostgreSQL/
      ext_management_system.connect(:service => "PostgresqlDatabaseService").delete_by_id(ems_ref)
    end
  rescue => err
    _log.error("cloud database=[#{name}], error: #{err}")
    raise
  end
end
