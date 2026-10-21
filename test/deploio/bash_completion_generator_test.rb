# frozen_string_literal: true

require "test_helper"
require "open3"
require "shellwords"

class BashCompletionGeneratorTest < Minitest::Test
  STUBBED_LISTS = <<~SH
    _deploio_apps_list() { echo "shop-main shop-develop"; }
    _deploio_projects_list() { echo "shop blog"; }
    _deploio_orgs_list() { echo "renuo nine"; }
    _deploio_pg_databases_list() { echo "shop-db"; }
  SH

  FAKE_DEPLOIO = <<~SH
    #!/bin/sh
    case "$1" in
      orgs) echo '[{"name":"renuo","current":true},{"name":"nine"}]' ;;
      apps) echo '[{"metadata":{"namespace":"renuo-shop","name":"main"}}]' ;;
      projects) echo '[{"metadata":{"name":"renuo-shop"}},{"metadata":{"name":"renuo"}}]' ;;
      pg) echo '[{"metadata":{"namespace":"renuo-shop","name":"db"}}]' ;;
    esac
  SH

  def setup
    @generator = Deploio::BashCompletionGenerator.new
  end

  def test_generate_registers_completion_for_both_executables
    assert_includes @generator.generate, "complete -F _deploio deploio depl"
  end

  def test_generate_uses_custom_program_name
    output = Deploio::BashCompletionGenerator.new(program_name: "mycli").generate

    assert_includes output, "complete -F _mycli mycli depl"
    assert_includes output, "_mycli_apps_list()"
  end

  def test_completes_top_level_commands
    candidates = complete("deploio", "")

    assert_includes candidates, "apps"
    assert_includes candidates, "logs"
    assert_includes candidates, "exec"
    assert_includes candidates, "completion"
    refute_includes candidates, "help"
  end

  def test_completes_top_level_command_prefix
    assert_equal ["apps"], complete("deploio", "ap")
  end

  def test_completes_top_level_flags
    assert_equal %w[-v --version].sort, complete("deploio", "-").sort
  end

  def test_completes_subcommand_commands
    assert_equal %w[info list], complete("deploio", "apps", "").sort
  end

  def test_completes_nested_subcommand_commands
    assert_equal %w[capture download list], complete("deploio", "pg", "backups", "").sort
  end

  def test_completes_command_flags
    assert_equal ["--tail"], complete("deploio", "logs", "--t")
  end

  def test_completes_default_task_flags_on_subcommand
    assert_includes complete("deploio", "apps", "--"), "--chf"
  end

  def test_completes_nested_command_flags
    assert_equal ["--db-name"], complete("deploio", "pg", "backups", "download", "--db")
  end

  def test_completes_app_option_values
    assert_equal %w[shop-develop shop-main], complete("deploio", "logs", "-a", "").sort
  end

  def test_completes_project_option_values
    assert_equal ["shop"], complete("deploio", "apps", "--project", "s")
  end

  def test_completes_positional_argument
    assert_equal %w[nine renuo], complete("deploio", "orgs", "set", "").sort
  end

  def test_skips_option_values_when_counting_positional_arguments
    assert_equal ["shop-db"], complete("deploio", "pg", "info", "--org", "renuo", "")
  end

  def test_does_not_complete_positional_argument_twice
    assert_empty complete("deploio", "pg", "info", "shop-db", "")
  end

  def test_completes_local_commands_after_passthrough_separator
    assert_includes complete("deploio", "exec", "-a", "shop-main", "--", "bas"), "bash"
  end

  def test_completes_for_depl_alias
    assert_equal ["apps"], complete("depl", "ap")
  end

  def test_orgs_list_prints_names
    assert_equal %w[renuo nine], list("orgs")
  end

  def test_apps_list_strips_current_org_from_namespace
    assert_equal ["shop-main"], list("apps")
  end

  def test_projects_list_strips_current_org_prefix
    assert_equal %w[shop renuo], list("projects")
  end

  def test_pg_databases_list_strips_current_org_from_namespace
    assert_equal ["shop-db"], list("pg_databases")
  end

  def test_cli_prints_bash_completion
    out, = capture_io do
      Deploio::CLI.start(["completion", "--shell", "bash"])
    end

    assert_includes out, "complete -F _deploio deploio depl"
  end

  private

  def complete(*words)
    run_bash(<<~SH).lines(chomp: true)
      #{@generator.generate}
      #{STUBBED_LISTS}
      COMP_WORDS=(#{words.map(&:shellescape).join(" ")})
      COMP_CWORD=#{words.size - 1}
      _deploio
      printf '%s\\n' "${COMPREPLY[@]}"
    SH
      .reject(&:empty?)
  end

  def list(name)
    Dir.mktmpdir do |dir|
      fake = File.join(dir, "deploio")
      File.write(fake, FAKE_DEPLOIO)
      File.chmod(0o755, fake)

      run_bash(<<~SH).lines(chomp: true)
        #{@generator.generate}
        PATH=#{dir.shellescape}:$PATH
        _deploio_#{name}_list
      SH
    end
  end

  # Bundler's RUBYOPT makes nested rubies prepend the gem bin dir to PATH,
  # which would shadow the fake deploio with the real one.
  def run_bash(script)
    out, status = Bundler.with_unbundled_env do
      Open3.capture2("bash", "--norc", "--noprofile", stdin_data: script)
    end
    assert status.success?, "bash exited with #{status.exitstatus}"
    out
  end
end
