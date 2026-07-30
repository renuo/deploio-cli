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

  DEDICATED_DB = {
    "kind" => "Postgres",
    "metadata" => {"namespace" => "myorg-myproject", "name" => "maindb"},
    "spec" => {"forProvider" => {"version" => "15"}},
    "status" => {
      "atProvider" => {"fqdn" => "db.example.com", "databases" => {"maindb" => {}}}
    }
  }.freeze

  ECONOMY_DB = {
    "kind" => "PostgresDatabase",
    "metadata" => {"namespace" => "myorg-myproject", "name" => "shareddb"},
    "spec" => {"forProvider" => {"version" => "17"}},
    "status" => {"atProvider" => {"name" => "1c62958_53f1258"}}
  }.freeze

  # setup_options builds its own NctlClient, so swap the constructor out to run
  # the real command against a mock.
  def run_backups_command(args, mock_client, expect_exit: false)
    capture_io do
      Deploio::NctlClient.stub(:new, mock_client) do
        if expect_exit
          assert_raises(SystemExit) { Deploio::Commands::PostgreSQLBackups.start(args) }
        else
          Deploio::Commands::PostgreSQLBackups.start(args)
        end
      end
    end
  end

  def test_pg_backups_capture_runs_the_backup_script_for_a_dedicated_instance
    mock_client = MockNctlClient.new(pg_databases: [DEDICATED_DB], current_org: "myorg")

    out, = run_backups_command(["capture", "myproject-maindb"], mock_client)

    assert_match(/ssh dbadmin@db\.example\.com sudo nine-postgresql-backup/, out)
  end

  def test_pg_backups_download_rsyncs_from_a_dedicated_instance
    mock_client = MockNctlClient.new(pg_databases: [DEDICATED_DB], current_org: "myorg")

    out, = run_backups_command(["download", "myproject-maindb"], mock_client)

    assert_match(
      %r{rsync -av dbadmin@db\.example\.com:~/backup/postgresql/latest/customer/maindb/maindb\.zst \./myproject-maindb-latest-backup\.zst},
      out
    )
  end

  def test_pg_backups_download_honours_the_output_option
    mock_client = MockNctlClient.new(pg_databases: [DEDICATED_DB], current_org: "myorg")

    out, = run_backups_command(["download", "myproject-maindb", "--output", "/tmp/mine.zst"], mock_client)

    assert_match(%r{maindb\.zst /tmp/mine\.zst}, out)
  end

  # What the tier classes refuse is their own business (and tested there); the
  # CLI's job is to report the refusal and exit non-zero instead of crashing.
  def test_pg_backups_capture_is_rejected_for_an_economy_database
    mock_client = MockNctlClient.new(pg_databases: [ECONOMY_DB], current_org: "myorg")

    out, err = run_backups_command(["capture", "myproject-shareddb"], mock_client, expect_exit: true)

    assert_empty out, "nothing should have been attempted"
    refute_empty err, "the reason should be reported on stderr"
  end

  def test_pg_backups_list_is_rejected_for_a_dedicated_instance
    mock_client = MockNctlClient.new(pg_databases: [DEDICATED_DB], current_org: "myorg")

    out, err = run_backups_command(["list", "myproject-maindb"], mock_client, expect_exit: true)

    assert_empty out, "nothing should have been attempted"
    refute_empty err, "the reason should be reported on stderr"
  end

  class MockNctlClient
    attr_reader :current_org

    def initialize(pg_databases: [], current_org: nil, dry_run: true)
      @pg_databases = pg_databases
      @current_org = current_org
      @dry_run = dry_run
    end

    def check_requirements = nil

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
