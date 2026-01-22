# frozen_string_literal: true

require "test_helper"
require "stringio"

class CLIAppsTest < Minitest::Test
  def test_apps_list_executes_correct_nctl_command
    out, = capture_io do
      Deploio::Commands::Apps.start(["list", "--dry-run"])
    end

    assert_match(/nctl get apps -A -o json/, out)
  end

  def test_apps_via_main_cli_executes_correct_nctl_command
    out, = capture_io do
      Deploio::CLI.start(["apps", "--dry-run"])
    end

    assert_match(/nctl get apps -A -o json/, out)
  end

  def test_apps_info_raises_error_when_app_not_found_in_dry_run
    # In dry-run mode, get_all_apps returns empty, so app resolution fails
    _out, err = capture_io do
      assert_raises(SystemExit) do
        Deploio::Commands::Apps.start(["info", "--app", "myproject-staging", "--dry-run"])
      end
    end

    assert_match(/App not found/, err)
  end
end
