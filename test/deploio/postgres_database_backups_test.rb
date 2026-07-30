# frozen_string_literal: true

require "test_helper"

class PostgresDatabaseBackupsTest < Minitest::Test
  PROJECT = "renuo-chess-tracker"
  INSTANCE_NAME = "1c62958_53f1258"

  def backup_bucket(name, endpoint: "cz42.objects.nineapis.ch")
    {
      "metadata" => {
        "name" => name,
        "namespace" => PROJECT,
        "labels" => {"nine.ch/controllerKind" => "DatabaseBackupSchedule"}
      },
      "status" => {"atProvider" => {"endpoint" => endpoint}}
    }
  end

  def plain_bucket(name)
    {
      "metadata" => {"name" => name, "namespace" => PROJECT, "labels" => {}},
      "status" => {"atProvider" => {"endpoint" => "es34.objects.nineapis.ch"}}
    }
  end

  def object(name, mod_time, size: 21_986)
    {"Name" => name, "Size" => size, "ModTime" => mod_time}
  end

  def db_ref(database_name = "main")
    Deploio::PgDatabaseRef.new(
      "#{PROJECT}-#{database_name}",
      available_databases: {
        "#{PROJECT}-#{database_name}" => {project_name: PROJECT, database_name: database_name}
      }
    )
  end

  def database_data(instance_name = INSTANCE_NAME)
    {
      "kind" => "PostgresDatabase",
      "metadata" => {"namespace" => PROJECT, "name" => "main"},
      "status" => {"atProvider" => {"name" => instance_name}}
    }
  end

  def build(buckets:, objects: [], database_name: "main", data: database_data)
    rclone = FakeRcloneClient.new(objects)
    backups = Deploio::PostgresDatabaseBackups.new(
      db_ref: db_ref(database_name),
      data: data,
      nctl_client: MockNctlClient.new(buckets: buckets),
      rclone_client_factory: -> { rclone }
    )
    [backups, rclone]
  end

  def test_finds_the_backup_bucket_named_after_the_database
    backups, rclone = build(
      buckets: [
        plain_bucket("chess-tracker-main"),
        backup_bucket("postgresdatabase-main-cffe5c3")
      ],
      objects: [object("PostgresDatabase-#{INSTANCE_NAME}-2026-07-30-0224.sql.zst", "2026-07-30T02:24:22Z")]
    )

    assert_equal 1, backups.backups.size
    assert_equal ["postgresdatabase-main-cffe5c3"], rclone.listed
  end

  def test_ignores_buckets_not_owned_by_a_backup_schedule
    backups, = build(buckets: [plain_bucket("postgresdatabase-main-cffe5c3")])

    error = assert_raises(Deploio::Error) { backups.backups }
    assert_match(/No backup bucket found/, error.message)
  end

  def test_does_not_match_the_bucket_of_a_similarly_named_database
    # Database "labels" must not pick up the bucket belonging to "labels-main".
    backups, = build(
      buckets: [backup_bucket("postgresdatabase-labels-main-be40f63")],
      database_name: "labels"
    )

    assert_raises(Deploio::Error) { backups.backups }
  end

  def test_matches_a_database_whose_name_contains_a_hyphen
    backups, rclone = build(
      buckets: [backup_bucket("postgresdatabase-labels-main-be40f63")],
      database_name: "labels-main"
    )

    assert_empty backups.backups
    assert_equal ["postgresdatabase-labels-main-be40f63"], rclone.listed
  end

  def test_raises_when_no_bucket_exists_for_the_project
    backups, = build(buckets: [])

    error = assert_raises(Deploio::Error) { backups.backups }
    assert_match(/backupSchedule/, error.message)
  end

  def test_keeps_only_objects_belonging_to_this_database
    backups, = build(
      buckets: [backup_bucket("postgresdatabase-main-cffe5c3")],
      objects: [
        object("PostgresDatabase-#{INSTANCE_NAME}-2026-07-29-0224.sql.zst", "2026-07-29T02:24:45Z"),
        object("PostgresDatabase-other_instance-2026-07-30-0224.sql.zst", "2026-07-30T02:24:22Z"),
        object("some-unrelated-file.txt", "2026-07-30T03:00:00Z")
      ]
    )

    assert_equal ["PostgresDatabase-#{INSTANCE_NAME}-2026-07-29-0224.sql.zst"],
      backups.backups.map { |b| b["Name"] }
  end

  def test_orders_backups_newest_first
    backups, = build(
      buckets: [backup_bucket("postgresdatabase-main-cffe5c3")],
      objects: [
        object("PostgresDatabase-#{INSTANCE_NAME}-2026-07-28-0227.sql.zst", "2026-07-28T02:27:37Z"),
        object("PostgresDatabase-#{INSTANCE_NAME}-2026-07-30-0224.sql.zst", "2026-07-30T02:24:22Z"),
        object("PostgresDatabase-#{INSTANCE_NAME}-2026-07-29-0224.sql.zst", "2026-07-29T02:24:45Z")
      ]
    )

    assert_equal %w[2026-07-30T02:24:22Z 2026-07-29T02:24:45Z 2026-07-28T02:27:37Z],
      backups.backups.map { |b| b["ModTime"] }
    assert_equal "PostgresDatabase-#{INSTANCE_NAME}-2026-07-30-0224.sql.zst", backups.latest["Name"]
  end

  def test_download_fetches_the_latest_backup
    backups, rclone = build(
      buckets: [backup_bucket("postgresdatabase-main-cffe5c3")],
      objects: [
        object("PostgresDatabase-#{INSTANCE_NAME}-2026-07-29-0224.sql.zst", "2026-07-29T02:24:45Z"),
        object("PostgresDatabase-#{INSTANCE_NAME}-2026-07-30-0224.sql.zst", "2026-07-30T02:24:22Z")
      ]
    )

    backup = backups.download(destination: "./out.sql.zst")

    assert_equal "PostgresDatabase-#{INSTANCE_NAME}-2026-07-30-0224.sql.zst", backup["Name"]
    assert_equal [[
      "postgresdatabase-main-cffe5c3",
      "PostgresDatabase-#{INSTANCE_NAME}-2026-07-30-0224.sql.zst",
      "./out.sql.zst"
    ]], rclone.downloaded
  end

  def test_download_raises_when_the_bucket_holds_no_backups
    backups, rclone = build(buckets: [backup_bucket("postgresdatabase-main-cffe5c3")])

    error = assert_raises(Deploio::Error) { backups.download(destination: "./out.sql.zst") }
    assert_match(/No backups found/, error.message)
    assert_empty rclone.downloaded
  end

  class FakeRcloneClient
    attr_reader :listed, :downloaded

    def initialize(objects = [])
      @objects = objects
      @listed = []
      @downloaded = []
    end

    def list(bucket)
      @listed << bucket
      @objects
    end

    def download(bucket, object, destination)
      @downloaded << [bucket, object, destination]
      true
    end
  end

  class MockNctlClient
    attr_reader :dry_run

    def initialize(buckets: [], dry_run: false)
      @buckets = buckets
      @dry_run = dry_run
    end

    def get_services_by_type(type, project:)
      raise ArgumentError, "unexpected type #{type}" unless type == "bucket"
      raise ArgumentError, "unexpected project #{project}" unless project == PROJECT

      @buckets
    end

    def get_bucket_user_access_key(_name, project:) = "access-key"

    def get_bucket_user_secret_key(_name, project:) = "secret-key"
  end
end
