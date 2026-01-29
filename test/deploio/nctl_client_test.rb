# frozen_string_literal: true

require "test_helper"

class NctlClientTest < Minitest::Test
  def setup
    @client = Deploio::NctlClient.new(dry_run: true)
    available_apps = {
      "renuotest-myproject-staging" => {project_name: "renuotest-myproject", app_name: "staging"}
    }
    @app_ref = Deploio::AppRef.new("renuotest-myproject-staging", available_apps: available_apps)
  end

  def test_dry_run_mode
    assert @client.dry_run
  end

  def test_logs_command_without_tail
    # In dry_run mode, commands are printed but not executed
    # We can capture stdout to verify the command is built correctly
    out, = capture_io do
      @client.logs(@app_ref, tail: false, lines: 100)
    end

    assert_match(/nctl logs app staging/, out)
    assert_match(/--project renuotest-myproject/, out)
    assert_match(/--lines=100/, out)
    refute_match(/-f/, out)
  end

  def test_logs_command_with_tail
    out, = capture_io do
      @client.logs(@app_ref, tail: true, lines: 50)
    end

    assert_match(/nctl logs app staging/, out)
    assert_match(/-f/, out)
    assert_match(/--lines=50/, out)
  end

  def test_get_all_apps_returns_empty_in_dry_run
    result = @client.get_all_apps
    assert_equal [], result
  end
end
