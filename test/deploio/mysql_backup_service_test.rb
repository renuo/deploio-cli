# frozen_string_literal: true

require "test_helper"

class MysqlBackupServiceTest < Minitest::Test
  def data(databases: {"maindb" => {}}, fqdn: "db.example.com")
    {
      "kind" => "MySQL",
      "status" => {"atProvider" => {"fqdn" => fqdn, "databases" => databases}}
    }
  end

  def service(**kwargs)
    Deploio::MysqlBackupService.new(data: data(**kwargs), name: "myproject-maindb", dry_run: true)
  end

  def test_listing_backups_is_unsupported
    assert_raises(Deploio::UnsupportedBackupOperationError) { service.backups }
  end

  def test_default_destination_is_named_after_the_database
    assert_equal "./myproject-maindb-latest-backup.zst", service.default_destination
  end

  def test_capture_runs_the_nine_backup_script_over_ssh
    out, = capture_io { service.capture }

    assert_match(/ssh dbadmin@db\.example\.com sudo nine-mysql-backup/, out)
  end

  def test_download_rsyncs_the_latest_backup
    out, = capture_io { service.download(destination: "./out.zst") }

    assert_match(
      %r{rsync -av dbadmin@db\.example\.com:~/backup/mysql/latest/customer/maindb/maindb\.zst \./out\.zst},
      out
    )
  end

  def test_download_uses_the_only_database_when_db_name_is_omitted
    out, = capture_io { service(databases: {"solo" => {}}).download(destination: "./out.zst") }

    assert_match(%r{customer/solo/solo\.zst}, out)
  end

  def test_download_uses_the_requested_database_when_there_are_several
    out, = capture_io do
      service(databases: {"one" => {}, "two" => {}}).download(destination: "./out.zst", db_name: "two")
    end

    assert_match(%r{customer/two/two\.zst}, out)
  end

  def test_download_raises_when_several_databases_and_none_requested
    error = assert_raises(Deploio::Error) do
      service(databases: {"one" => {}, "two" => {}}).download(destination: "./out.zst")
    end

    assert_match(/Multiple databases found/, error.message)
    assert_match(/one, two/, error.message)
  end

  def test_download_raises_when_the_instance_has_no_databases
    error = assert_raises(Deploio::Error) do
      service(databases: {"" => {}}).download(destination: "./out.zst")
    end

    assert_match(/No databases found/, error.message)
  end

  def test_raises_when_the_fqdn_is_missing
    error = assert_raises(Deploio::Error) { service(fqdn: "").capture }

    assert_match(/FQDN not found/, error.message)
  end
end
