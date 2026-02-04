# frozen_string_literal: true

require "test_helper"

class PgDatabaseResolverTest < Minitest::Test
  def setup
    @nctl = MockNctlClient.new(dry_run: true)
  end

  def test_raises_error_when_database_not_found_in_dry_run
    # In dry_run mode, get_all_pg_databases returns empty, so database won't be found
    resolver = Deploio::PgDatabaseResolver.new(nctl_client: @nctl)

    error = assert_raises(Deploio::PgDatabaseNotFoundError) do
      resolver.resolve(database_name: "myproject-maindb")
    end

    assert_match(/Database not found/, error.message)
  end

  def test_raises_error_when_no_database_specified
    resolver = Deploio::PgDatabaseResolver.new(nctl_client: @nctl)

    error = assert_raises(Deploio::Error) { resolver.resolve }

    assert_match(/No database specified/, error.message)
  end

  def test_resolves_from_available_databases
    nctl = MockNctlClient.new(pg_databases: [
      {"metadata" => {"namespace" => "n10518", "name" => "maindb"}}
    ])
    resolver = Deploio::PgDatabaseResolver.new(nctl_client: nctl)

    result = resolver.resolve(database_name: "n10518-maindb")

    assert_equal "n10518", result.project_name
    assert_equal "maindb", result.database_name
  end

  def test_resolves_short_name_with_current_org
    nctl = MockNctlClient.new(
      pg_databases: [{"metadata" => {"namespace" => "myorg-myproject", "name" => "postgres"}}],
      current_org: "myorg"
    )
    resolver = Deploio::PgDatabaseResolver.new(nctl_client: nctl)

    # Can resolve using short name (without org prefix)
    result = resolver.resolve(database_name: "myproject-postgres")

    assert_equal "myorg-myproject", result.project_name
    assert_equal "postgres", result.database_name
  end

  def test_available_databases_hash_includes_both_full_and_short_names
    nctl = MockNctlClient.new(
      pg_databases: [
        {"metadata" => {"namespace" => "myorg-myproject", "name" => "maindb"}},
        {"metadata" => {"namespace" => "otherorg-project", "name" => "testdb"}}
      ],
      current_org: "myorg"
    )
    resolver = Deploio::PgDatabaseResolver.new(nctl_client: nctl)

    hash = resolver.available_databases_hash

    # Full names should be present
    assert hash.key?("myorg-myproject-maindb")
    assert hash.key?("otherorg-project-testdb")

    # Short name should be present only for databases in current org
    assert hash.key?("myproject-maindb")
    refute hash.key?("project-testdb")
  end

  def test_short_name_for_strips_org_prefix
    nctl = MockNctlClient.new(current_org: "myorg")
    resolver = Deploio::PgDatabaseResolver.new(nctl_client: nctl)

    assert_equal "myproject-maindb", resolver.short_name_for("myorg-myproject", "maindb")
  end

  def test_short_name_for_keeps_full_name_without_org
    nctl = MockNctlClient.new(current_org: nil)
    resolver = Deploio::PgDatabaseResolver.new(nctl_client: nctl)

    assert_equal "someorg-myproject-postgres", resolver.short_name_for("someorg-myproject", "postgres")
  end

  def test_short_name_for_with_different_org
    nctl = MockNctlClient.new(current_org: "myorg")
    resolver = Deploio::PgDatabaseResolver.new(nctl_client: nctl)

    # Database from different org should keep full namespace
    assert_equal "otherorg-project-db", resolver.short_name_for("otherorg-project", "db")
  end

  def test_available_databases_hash_handles_missing_metadata
    nctl = MockNctlClient.new(
      pg_databases: [
        {"metadata" => {"namespace" => "valid-project", "name" => "db"}},
        {"metadata" => {"namespace" => "", "name" => ""}}, # Empty strings
        {} # Missing metadata entirely
      ]
    )
    resolver = Deploio::PgDatabaseResolver.new(nctl_client: nctl)

    hash = resolver.available_databases_hash

    # Should include databases with valid metadata (even if empty strings create a key)
    # The implementation creates "-" as a key for empty namespace/name
    assert hash.key?("valid-project-db")
    assert hash.key?("-") # Empty namespace and name create this key
  end

  def test_available_databases_hash_handles_errors_gracefully
    nctl = MockNctlClient.new(error_on_get: true)
    resolver = Deploio::PgDatabaseResolver.new(nctl_client: nctl)

    hash = resolver.available_databases_hash

    # Should return empty hash on error
    assert_equal({}, hash)
  end

  class MockNctlClient
    attr_reader :current_org, :dry_run

    def initialize(pg_databases: [], current_org: nil, dry_run: false, error_on_get: false)
      @pg_databases = pg_databases
      @current_org = current_org
      @dry_run = dry_run
      @error_on_get = error_on_get
    end

    def get_all_pg_databases
      raise "Simulated error" if @error_on_get

      @pg_databases
    end

    def get_pg_database(db_ref)
      @pg_databases.find do |db|
        metadata = db["metadata"] || {}
        metadata["namespace"] == db_ref.project_name &&
          metadata["name"] == db_ref.database_name
      end
    end
  end
end
