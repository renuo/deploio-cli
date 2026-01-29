# frozen_string_literal: true

require "test_helper"
require "stringio"

class CLIProjectsTest < Minitest::Test
  def test_projects_list_executes_correct_nctl_command
    out, = capture_io do
      Deploio::Commands::Projects.start(["list", "--dry-run"])
    end

    assert_match(/nctl get projects -o json/, out)
  end

  def test_projects_via_main_cli_executes_correct_nctl_command
    out, = capture_io do
      Deploio::CLI.start(["projects", "--dry-run"])
    end

    assert_match(/nctl get projects -o json/, out)
  end
end
