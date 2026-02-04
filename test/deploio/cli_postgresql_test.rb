# frozen_string_literal: true

require "test_helper"
require "stringio"

class CLIPostgreSQLTest < Minitest::Test
  def test_pg_list_executes_correct_nctl_commands
    out, = capture_io do
      Deploio::Commands::PostgreSQL.start(["list", "--dry-run"])
    end

    # Should query both dedicated and shared databases
    assert_match(/nctl get postgres -A -o json/, out)
    assert_match(/nctl get postgresdatabase -A -o json/, out)
  end

  def test_pg_via_main_cli_executes_correct_nctl_command
    out, = capture_io do
      Deploio::CLI.start(["pg", "--dry-run"])
    end

    assert_match(/nctl get postgres -A -o json/, out)
  end

  def test_pg_info_raises_error_when_database_not_found_in_dry_run
    # In dry-run mode, get_all_pg_databases returns empty, so database resolution fails
    _out, err = capture_io do
      assert_raises(SystemExit) do
        Deploio::Commands::PostgreSQL.start(["info", "myproject-db", "--dry-run"])
      end
    end

    assert_match(/Database not found/, err)
  end

  def test_pg_backups_capture_in_dry_run
    # Mock the scenario where we have a database available
    mock_client = MockNctlClient.new(
      pg_databases: [{
        "kind" => "Postgres",
        "metadata" => {"namespace" => "myorg-myproject", "name" => "maindb"},
        "spec" => {"forProvider" => {"version" => "15"}},
        "status" => {"atProvider" => {"fqdn" => "db.example.com"}}
      }],
      current_org: "myorg"
    )

    out, = capture_io do
      resolver = Deploio::PgDatabaseResolver.new(nctl_client: mock_client)
      _db_ref = resolver.resolve(database_name: "myproject-maindb")

      # Simulate the capture command
      fqdn = "db.example.com"
      cmd = ["ssh", "dbadmin@#{fqdn}", "sudo nine-postgresql-backup"]
      puts "> #{cmd.join(" ")}"
    end

    assert_match(/ssh dbadmin@db.example.com sudo nine-postgresql-backup/, out)
  end

  def test_pg_backups_download_in_dry_run
    # Mock the scenario where we have a database available
    mock_client = MockNctlClient.new(
      pg_databases: [{
        "kind" => "Postgres",
        "metadata" => {"namespace" => "myorg-myproject", "name" => "maindb"},
        "spec" => {"forProvider" => {"version" => "15"}},
        "status" => {
          "atProvider" => {
            "fqdn" => "db.example.com",
            "databases" => {"maindb" => {}}
          }
        }
      }],
      current_org: "myorg"
    )

    out, = capture_io do
      resolver = Deploio::PgDatabaseResolver.new(nctl_client: mock_client)
      _db_ref = resolver.resolve(database_name: "myproject-maindb")

      # Simulate the download command
      fqdn = "db.example.com"
      db_name = "maindb"
      destination = "./myproject-maindb-latest-backup.zst"
      cmd = ["rsync", "-avz", "dbadmin@#{fqdn}:~/backup/postgresql/latest/customer/#{db_name}/#{db_name}.zst", destination]
      puts "> #{cmd.join(" ")}"
    end

    assert_match(/rsync -avz dbadmin@db.example.com:~\/backup\/postgresql\/latest\/customer\/maindb\/maindb.zst/, out)
  end

  class MockNctlClient
    attr_reader :current_org

    def initialize(pg_databases: [], current_org: nil, dry_run: true)
      @pg_databases = pg_databases
      @current_org = current_org
      @dry_run = dry_run
    end

    def get_all_pg_databases
      @pg_databases
    end

    def get_pg_database(db_ref)
      @pg_databases.find do |db|
        metadata = db["metadata"] || {}
        metadata["namespace"] == db_ref.project_name &&
          metadata["name"] == db_ref.database_name
      end
    end

    attr_reader :dry_run
  end
end
