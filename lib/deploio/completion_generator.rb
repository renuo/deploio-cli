# frozen_string_literal: true

require "erb"

module Deploio
  # Generates zsh completion script from Thor command metadata.
  # Can be reused with any Thor-based CLI by passing the CLI class.
  #
  # @example Basic usage
  #   CompletionGenerator.new(MyCLI).generate
  #
  # @example With custom option completers
  #   CompletionGenerator.new(MyCLI, option_completers: {
  #     'env' => 'environment:(production staging development)'
  #   }).generate
  #
  class CompletionGenerator
    TEMPLATE_PATH = File.expand_path("templates/completion.zsh.erb", __dir__)

    # Commands that pass through to external programs (like exec)
    # These get '*:command:_normal' as their final argument
    PASSTHROUGH_COMMANDS = %w[exec run].freeze

    attr_reader :cli_class, :option_completers, :positional_completers, :program_name

    # @param cli_class [Class] Thor CLI class to generate completions for
    # @param option_completers [Hash] Custom completers for specific options
    #   e.g., { 'app' => 'app:_myapp_apps_list' }
    # @param positional_completers [Hash] Custom completers for positional args
    #   e.g., { 'orgs:set' => "'1:organization:_myapp_orgs_list'" }
    # @param program_name [String] Override the program name (default: derived from CLI class)
    def initialize(cli_class = nil, option_completers: {}, positional_completers: {}, program_name: nil)
      @cli_class = cli_class || default_cli_class
      @program_name = program_name || derive_program_name
      @option_completers = default_option_completers.merge(option_completers)
      @positional_completers = default_positional_completers.merge(positional_completers)
    end

    def generate
      template = File.read(TEMPLATE_PATH)
      ERB.new(template, trim_mode: "-").result(binding)
    end

    private

    def default_cli_class
      require_relative "cli"
      CLI
    end

    def default_option_completers
      {
        "app" => "app:_#{program_name}_apps_list",
        "size" => "size:(micro mini standard)"
      }
    end

    def default_positional_completers
      {
        "orgs:set" => "'1:organization:_#{program_name}_orgs_list'"
      }
    end

    def derive_program_name
      # Convert "Deploio::CLI" -> "deploio", "MyApp::CLI" -> "myapp"
      cli_class.name.split("::").first.downcase
    end

    def subcommands
      cli_class.subcommand_classes.map do |name, klass|
        commands = klass.commands.except("help").map do |cmd_name, cmd|
          [cmd_name, cmd.description, cmd.options]
        end
        [name, commands, klass.class_options]
      end
    end

    def main_commands
      cli_class.commands.except("help").map do |name, cmd|
        [name, cmd.description]
      end
    end

    def direct_commands
      subcommand_names = cli_class.subcommands
      cli_class.commands.reject do |name, _|
        name == "help" || subcommand_names.include?(name) || passthrough_command?(name)
      end.map do |name, cmd|
        [name, cmd.options]
      end
    end

    def passthrough_commands
      PASSTHROUGH_COMMANDS.filter_map do |name|
        cmd = cli_class.commands[name]
        [name, cmd.options] if cmd
      end
    end

    def passthrough_command?(name)
      PASSTHROUGH_COMMANDS.include?(name)
    end

    def cli_class_options
      cli_class.class_options
    end

    def positional_arg(subcommand, cmd_name)
      positional_completers["#{subcommand}:#{cmd_name}"]
    end

    def format_options(method_options, class_options, extra_arg = nil)
      all_options = cli_class.class_options.merge(class_options).merge(method_options)
      lines = all_options.map { |name, opt| format_option(name, opt) }.compact
      lines << extra_arg if extra_arg

      return "            # No options" if lines.empty?

      lines.map.with_index do |line, i|
        continuation = (i < lines.size - 1) ? " \\" : ""
        "            #{line}#{continuation}"
      end.join("\n")
    end

    def format_option(name, opt)
      flag = name.to_s.tr("_", "-")
      short = opt.aliases&.first
      desc = escape(opt.description || "")
      completer = option_completer(name, flag)

      if short
        if opt.type == :boolean
          "'(#{short} --#{flag})'{#{short},--#{flag}}'[#{desc}]'"
        else
          "'(#{short} --#{flag})'{#{short},--#{flag}}'[#{desc}]:#{completer}'"
        end
      elsif opt.type == :boolean
        "'--#{flag}[#{desc}]'"
      else
        "'--#{flag}[#{desc}]:#{completer}'"
      end
    end

    def option_completer(name, flag)
      option_completers[name.to_s] || "#{flag}:"
    end

    def escape(text)
      text.to_s.gsub("'", "'\\''").gsub("[", '\\[').gsub("]", '\\]')
    end
  end
end
