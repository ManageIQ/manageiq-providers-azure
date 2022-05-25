describe ManageIQ::Providers::Azure::CloudManager::CloudDatabase do
  require 'azure-armrest'

  let(:ems) do
    FactoryBot.create(:ems_azure)
  end

  let(:cloud_database) do
    FactoryBot.create(:cloud_database_azure, :ext_management_system => ems, :name => "test-db")
  end

  let(:config) do
    double(":Azure::Armrest::Configuration")
  end

  describe 'sql database actions' do
    let(:db_client) do
      double("::Azure::Armrest::Sql::SqlDatabaseService")
    end

    before do
      allow(ems).to receive(:connect).and_return(db_client)
    end

    it 'creates a SQL database' do
      expect(db_client).to receive(:create).with("test-server", cloud_database.name, "test-group", {:location => ems.provider_region})
      cloud_database.class.raw_create_cloud_database(ems, {:name           => cloud_database.name,
                                                           :server         => "test-server",
                                                           :database       => "SQL",
                                                           :resource_group => "test-group"})
    end

    it 'delete a SQL database' do
      expect(db_client).to receive(:delete_by_id).with(cloud_database.ems_ref)
      cloud_database.db_engine = "SQL Server"
      cloud_database.delete_cloud_database
    end
  end

  describe 'mariadb database actions' do
    let(:db_client) do
      double("::Azure::Armrest::Sql::MariadbDatabaseService")
    end

    before do
      allow(ems).to receive(:connect).and_return(db_client)
    end

    it 'creates a MariaDB database' do
      expect(db_client).to receive(:create).with("test-server", cloud_database.name, "test-group", {:location => ems.provider_region})
      cloud_database.class.raw_create_cloud_database(ems, {:name           => cloud_database.name,
                                                           :server         => "test-server",
                                                           :database       => "MariaDB",
                                                           :resource_group => "test-group"})
    end

    it 'delete a MariaDB database' do
      expect(db_client).to receive(:delete_by_id).with(cloud_database.ems_ref)
      cloud_database.db_engine = "MariaDB"
      cloud_database.delete_cloud_database
    end
  end

  describe 'mysql database actions' do
    let(:db_client) do
      double("::Azure::Armrest::Sql::MysqlDatabaseService")
    end

    before do
      allow(ems).to receive(:connect).and_return(db_client)
    end

    it 'creates a MySQL database' do
      expect(db_client).to receive(:create).with("test-server", cloud_database.name, "test-group", {:location => ems.provider_region})
      cloud_database.class.raw_create_cloud_database(ems, {:name           => cloud_database.name,
                                                           :server         => "test-server",
                                                           :database       => "MySQL",
                                                           :resource_group => "test-group"})
    end

    it 'delete a MySQL database' do
      expect(db_client).to receive(:delete_by_id).with(cloud_database.ems_ref)
      cloud_database.db_engine = "MySQL"
      cloud_database.delete_cloud_database
    end
  end

  describe 'postgresql database actions' do
    let(:db_client) do
      double("::Azure::Armrest::Sql::PostgresqlDatabaseService")
    end

    before do
      allow(ems).to receive(:connect).and_return(db_client)
    end

    it 'creates a PostgreSQL database' do
      expect(db_client).to receive(:create).with("test-server", cloud_database.name, "test-group", {:location => ems.provider_region})
      cloud_database.class.raw_create_cloud_database(ems, {:name           => cloud_database.name,
                                                           :server         => "test-server",
                                                           :database       => "PostgreSQL",
                                                           :resource_group => "test-group"})
    end

    it 'delete a PostgreSQL database' do
      expect(db_client).to receive(:delete_by_id).with(cloud_database.ems_ref)
      cloud_database.db_engine = "PostgreSQL"
      cloud_database.delete_cloud_database
    end
  end
end
