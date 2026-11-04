# frozen_string_literal: true

require_relative "completion_generator"

module Deploio
  # Generates bash completion script from Thor command metadata.
  # Completers are shell commands printing the candidates.
  #
  # @example With custom option completers
  #   BashCompletionGenerator.new(MyCLI, option_completers: {
  #     'env' => 'echo production staging development'
  #   }).generate
  #
  class BashCompletionGenerator < CompletionGenerator
    TEMPLATE_PATH = File.expand_path("templates/completion.bash.erb", __dir__)

    ROOT_OPTIONS = {version: Thor::Option.new(:version, type: :boolean, aliases: "-v")}.freeze

    # A command path ("" is the root, "pg:backups" a nested subcommand)
    # with the candidates that can follow it.
    Context = Struct.new(:path, :commands, :options, :positional, :passthrough, keyword_init: true)

    private

    def default_option_completers
      {
        "app" => "_#{program_name}_apps_list",
        "size" => "echo micro mini standard",
        "project" => "_#{program_name}_projects_list"
      }
    end

    def default_positional_completers
      {
        "orgs:set" => "_#{program_name}_orgs_list",
        "pg:info" => "_#{program_name}_pg_databases_list",
        "pg:backups:capture" => "_#{program_name}_pg_databases_list",
        "pg:backups:list" => "_#{program_name}_pg_databases_list",
        "pg:backups:download" => "_#{program_name}_pg_databases_list"
      }
    end

    def contexts
      @contexts ||= [
        Context.new(path: "", commands: main_commands.map(&:first), options: ROOT_OPTIONS),
        *direct_commands.map { |name, options| leaf_context(name, all_options(options)) },
        *passthrough_commands.map { |name, options| leaf_context(name, all_options(options), passthrough: true) },
        *subcommands.flat_map do |name, commands, class_options, default_task, klass|
          group_contexts(name, commands, class_options, default_task, klass.subcommand_classes)
        end,
        *nested_subcommands.flat_map do |name, commands, class_options|
          group_contexts(name, commands, class_options)
        end
      ]
    end

    def group_contexts(name, commands, class_options, default_task = nil, nested = {})
      default_options = commands.find { |cmd_name, _, _| cmd_name == default_task }&.last || {}
      group = Context.new(path: name, commands: commands.map(&:first),
        options: all_options(default_options, class_options))

      leaves = commands.reject { |cmd_name, _, _| nested.key?(cmd_name) }.map do |cmd_name, _, options|
        leaf_context("#{name}:#{cmd_name}", all_options(options, class_options))
      end

      [group, *leaves]
    end

    def leaf_context(path, options, passthrough: false)
      Context.new(path: path, commands: [], options: options,
        positional: positional_completers[path], passthrough: passthrough)
    end

    def all_options(method_options, class_options = {})
      cli_class_options.merge(class_options).merge(method_options)
    end

    def flags(context)
      context.options.flat_map { |name, opt| option_flags(name, opt) }.uniq
    end

    def value_flags(context)
      context.options.reject { |_, opt| opt.type == :boolean }.flat_map { |name, opt| option_flags(name, opt) }.uniq
    end

    def option_value_completers
      contexts.flat_map { |context| context.options.to_a }.uniq(&:first).filter_map do |name, opt|
        completer = option_completers[name.to_s]
        [option_flags(name, opt), completer] if completer
      end
    end

    def option_flags(name, opt)
      ["--#{name.to_s.tr("_", "-")}", *opt.aliases]
    end
  end
end
