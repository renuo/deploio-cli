# frozen_string_literal: true

require "test_helper"

class CompletionGeneratorTest < Minitest::Test
  def setup
    @generator = Deploio::CompletionGenerator.new
  end

  def test_main_commands_includes_all_cli_commands
    commands = @generator.send(:main_commands)
    command_names = commands.map(&:first)

    assert_includes command_names, "version"
    assert_includes command_names, "completion"
    assert_includes command_names, "logs"
    assert_includes command_names, "login"
    assert_includes command_names, "logout"
    assert_includes command_names, "whoami"
    assert_includes command_names, "exec"
    refute_includes command_names, "help"
  end

  def test_main_commands_includes_subcommand_entries
    commands = @generator.send(:main_commands)
    command_names = commands.map(&:first)

    assert_includes command_names, "auth"
    assert_includes command_names, "apps"
    assert_includes command_names, "orgs"
  end

  def test_main_commands_returns_name_and_description_pairs
    commands = @generator.send(:main_commands)

    commands.each do |name, description|
      assert_kind_of String, name
      assert_kind_of String, description
      refute_empty description, "Command '#{name}' should have a description"
    end
  end

  def test_direct_commands_excludes_subcommands
    commands = @generator.send(:direct_commands)
    command_names = commands.map(&:first)

    refute_includes command_names, "auth"
    refute_includes command_names, "apps"
    refute_includes command_names, "orgs"
  end

  def test_direct_commands_excludes_passthrough_commands
    commands = @generator.send(:direct_commands)
    command_names = commands.map(&:first)

    refute_includes command_names, "exec"
    refute_includes command_names, "run"
  end

  def test_direct_commands_excludes_help
    commands = @generator.send(:direct_commands)
    command_names = commands.map(&:first)

    refute_includes command_names, "help"
  end

  def test_direct_commands_includes_regular_commands
    commands = @generator.send(:direct_commands)
    command_names = commands.map(&:first)

    assert_includes command_names, "version"
    assert_includes command_names, "completion"
    assert_includes command_names, "logs"
  end

  def test_direct_commands_returns_name_and_options_pairs
    commands = @generator.send(:direct_commands)

    commands.each do |name, options|
      assert_kind_of String, name
      assert_kind_of Hash, options
    end
  end

  def test_subcommands_returns_all_subcommand_groups
    subcommands = @generator.send(:subcommands)
    subcommand_names = subcommands.map(&:first)

    assert_includes subcommand_names, "auth"
    assert_includes subcommand_names, "apps"
    assert_includes subcommand_names, "orgs"
  end

  def test_subcommands_returns_nested_commands
    subcommands = @generator.send(:subcommands)
    auth_subcommand = subcommands.find { |name, _, _| name == "auth" }

    refute_nil auth_subcommand
    name, commands, class_options = auth_subcommand

    assert_equal "auth", name
    assert_kind_of Array, commands
    assert_kind_of Hash, class_options

    command_names = commands.map(&:first)
    assert_includes command_names, "login"
    assert_includes command_names, "logout"
    assert_includes command_names, "whoami"
    refute_includes command_names, "help"
  end

  def test_subcommands_commands_have_name_description_and_options
    subcommands = @generator.send(:subcommands)

    subcommands.each do |_name, commands, _class_options|
      commands.each do |cmd_name, description, options|
        assert_kind_of String, cmd_name
        assert_kind_of String, description
        assert_kind_of Hash, options
      end
    end
  end

  def test_passthrough_commands_includes_exec
    commands = @generator.send(:passthrough_commands)
    command_names = commands.map(&:first)

    assert_includes command_names, "exec"
  end

  def test_passthrough_commands_returns_name_and_options
    commands = @generator.send(:passthrough_commands)

    commands.each do |name, options|
      assert_kind_of String, name
      assert_kind_of Hash, options
    end
  end

  def test_program_name_derived_from_cli_class
    assert_equal "deploio", @generator.program_name
  end

  def test_custom_program_name
    generator = Deploio::CompletionGenerator.new(program_name: "myapp")

    assert_equal "myapp", generator.program_name
  end

  def test_generate_produces_valid_zsh_script
    output = @generator.generate

    assert_includes output, "#compdef deploio depl"
    assert_includes output, "compdef _deploio deploio depl"
    assert_includes output, "_deploio()"
    assert_includes output, "_deploio_auth()"
    assert_includes output, "_deploio_apps()"
    assert_includes output, "_deploio_apps_list()"
    assert_includes output, "_deploio_orgs_list()"
  end

  def test_generate_uses_custom_program_name
    generator = Deploio::CompletionGenerator.new(program_name: "mycli")
    output = generator.generate

    assert_includes output, "#compdef mycli depl"
    assert_includes output, "compdef _mycli mycli depl"
    assert_includes output, "_mycli()"
    assert_includes output, "_mycli_auth()"
  end
end
