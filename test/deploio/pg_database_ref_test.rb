# frozen_string_literal: true

require "test_helper"

class PgDatabaseRefTest < Minitest::Test
  def test_parses_full_name_from_available_databases
    available = {
      "n10518-maindb" => {project_name: "n10518", database_name: "maindb"}
    }
    db_ref = Deploio::PgDatabaseRef.new("n10518-maindb", available_databases: available)

    assert_equal "n10518", db_ref.project_name
    assert_equal "maindb", db_ref.database_name
    assert_equal "n10518-maindb", db_ref.full_name
  end

  def test_full_name_method
    available = {
      "myproject-postgres" => {project_name: "myproject", database_name: "postgres"}
    }
    db_ref = Deploio::PgDatabaseRef.new("myproject-postgres", available_databases: available)

    assert_equal "myproject-postgres", db_ref.full_name
  end

  def test_to_s_returns_full_name
    available = {
      "proj-db" => {project_name: "proj", database_name: "db"}
    }
    db_ref = Deploio::PgDatabaseRef.new("proj-db", available_databases: available)

    assert_equal "proj-db", db_ref.to_s
  end

  def test_equality_comparison
    available = {
      "proj-db1" => {project_name: "proj", database_name: "db1"},
      "proj-db2" => {project_name: "proj", database_name: "db2"}
    }

    db_ref1 = Deploio::PgDatabaseRef.new("proj-db1", available_databases: available)
    db_ref1_copy = Deploio::PgDatabaseRef.new("proj-db1", available_databases: available)
    db_ref2 = Deploio::PgDatabaseRef.new("proj-db2", available_databases: available)

    assert_equal db_ref1, db_ref1_copy
    refute_equal db_ref1, db_ref2
  end

  def test_raises_error_when_database_not_found
    available = {
      "existing-db" => {project_name: "existing", database_name: "db"}
    }

    error = assert_raises(Deploio::PgDatabaseNotFoundError) do
      Deploio::PgDatabaseRef.new("nonexistent-db", available_databases: available)
    end

    assert_match(/Database not found: 'nonexistent-db'/, error.message)
    assert_match(/Run 'deploio pg' to see available Postgres databases/, error.message)
  end

  def test_suggests_similar_database_names
    available = {
      "myproject-maindb" => {project_name: "myproject", database_name: "maindb"},
      "myproject-testdb" => {project_name: "myproject", database_name: "testdb"}
    }

    error = assert_raises(Deploio::PgDatabaseNotFoundError) do
      Deploio::PgDatabaseRef.new("myproject-maindv", available_databases: available)
    end

    assert_match(/Did you mean\?/, error.message)
    assert_match(/myproject-maindb/, error.message)
  end

  def test_raises_error_when_no_databases_available
    error = assert_raises(Deploio::PgDatabaseNotFoundError) do
      Deploio::PgDatabaseRef.new("some-db", available_databases: {})
    end

    assert_match(/Database not found/, error.message)
  end
end
