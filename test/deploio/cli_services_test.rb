# frozen_string_literal: true

require "test_helper"
require "stringio"

class CLIServicesTest < Minitest::Test
  def test_services_list_queries_all_service_types
    out, = capture_io do
      Deploio::Commands::Services.start(["list", "--dry-run"])
    end

    # Should query all service types
    assert_match(/nctl get keyvaluestore -A -o json/, out)
    assert_match(/nctl get postgres -A -o json/, out)
    assert_match(/nctl get mysql -A -o json/, out)
    assert_match(/nctl get opensearch -A -o json/, out)
  end

  def test_services_default_task_is_list
    out, = capture_io do
      Deploio::Commands::Services.start(["--dry-run"])
    end

    # Default task should query all service types
    assert_match(/nctl get keyvaluestore -A -o json/, out)
  end

  def test_services_via_main_cli_default_task
    out, = capture_io do
      Deploio::CLI.start(["services", "--dry-run"])
    end

    assert_match(/nctl get keyvaluestore -A -o json/, out)
  end

  def test_services_list_with_project_filter
    out, = capture_io do
      Deploio::Commands::Services.start(["list", "--project", "myproject", "--dry-run"])
    end

    # Should query with project filter instead of -A
    assert_match(/nctl get keyvaluestore --project.*myproject -o json/, out)
    assert_match(/nctl get postgres --project.*myproject -o json/, out)
    assert_match(/nctl get mysql --project.*myproject -o json/, out)
    assert_match(/nctl get opensearch --project.*myproject -o json/, out)
  end

  def test_services_list_with_project_filter_via_main_cli
    out, = capture_io do
      Deploio::CLI.start(["services", "-p", "myproject", "--dry-run"])
    end

    assert_match(/nctl get keyvaluestore --project.*myproject -o json/, out)
  end
end
