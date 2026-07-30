# frozen_string_literal: true

require "test_helper"

class PostgresBackupsTest < Minitest::Test
  def data(databases: {"maindb" => {}}, fqdn: "db.example.com")
    {
      "kind" => "Postgres",
      "status" => {"atProvider" => {"fqdn" => fqdn, "databases" => databases}}
    }
  end

  def backups(**kwargs)
    Deploio::PostgresBackups.new(data: data(**kwargs), dry_run: true)
  end

  def test_capture_runs_the_nine_backup_script_over_ssh
    out, = capture_io { backups.capture }

    assert_match(/ssh dbadmin@db\.example\.com sudo nine-postgresql-backup/, out)
  end

  def test_download_rsyncs_the_latest_backup
    out, = capture_io { backups.download(destination: "./out.zst") }

    assert_match(
      %r{rsync -avz dbadmin@db\.example\.com:~/backup/postgresql/latest/customer/maindb/maindb\.zst \./out\.zst},
      out
    )
  end

  def test_download_uses_the_only_database_when_db_name_is_omitted
    out, = capture_io { backups(databases: {"solo" => {}}).download(destination: "./out.zst") }

    assert_match(%r{customer/solo/solo\.zst}, out)
  end

  def test_download_uses_the_requested_database_when_there_are_several
    out, = capture_io do
      backups(databases: {"one" => {}, "two" => {}}).download(destination: "./out.zst", db_name: "two")
    end

    assert_match(%r{customer/two/two\.zst}, out)
  end

  def test_download_raises_when_several_databases_and_none_requested
    error = assert_raises(Deploio::Error) do
      backups(databases: {"one" => {}, "two" => {}}).download(destination: "./out.zst")
    end

    assert_match(/Multiple databases found/, error.message)
    assert_match(/one, two/, error.message)
  end

  def test_download_raises_when_the_instance_has_no_databases
    error = assert_raises(Deploio::Error) do
      backups(databases: {"" => {}}).download(destination: "./out.zst")
    end

    assert_match(/No databases found/, error.message)
  end

  def test_raises_when_the_fqdn_is_missing
    error = assert_raises(Deploio::Error) { backups(fqdn: "").capture }

    assert_match(/FQDN not found/, error.message)
  end
end
