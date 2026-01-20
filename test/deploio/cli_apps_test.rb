# frozen_string_literal: true

require 'test_helper'
require 'stringio'

class CLIAppsTest < Minitest::Test
  def test_apps_list_executes_correct_nctl_command
    out, = capture_io do
      Deploio::Commands::Apps.start(['list', '--dry-run'])
    end

    assert_match(/nctl get apps -A -o json/, out)
  end

  def test_apps_via_main_cli_executes_correct_nctl_command
    out, = capture_io do
      Deploio::CLI.start(['apps', '--dry-run'])
    end

    assert_match(/nctl get apps -A -o json/, out)
  end
end
