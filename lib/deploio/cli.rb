# frozen_string_literal: true

require "thor"
require_relative "commands/auth"
require_relative "commands/apps"
require_relative "commands/builds"
require_relative "commands/orgs"
require_relative "commands/projects"
require_relative "commands/services"
require_relative "completion_generator"

module Deploio
  class CLI < Thor
    include SharedOptions

    desc "version", "Show version"
    def version
      puts "deploio-cli #{Deploio::VERSION}"
    end
    map %w[-v --version] => :version

    desc "completion", "Generate shell completion script"
    method_option :shell, aliases: "-s", type: :string, default: "zsh",
      desc: "Shell type (zsh, bash, fish)"
    def completion
      case options[:shell].downcase
      when "zsh"
        puts CompletionGenerator.new.generate
      when "bash", "fish"
        Output.error("#{options[:shell]} completion is not yet supported. Only zsh is available.")
        exit 1
      else
        Output.error("Unknown shell: #{options[:shell]}. Supported: zsh")
        exit 1
      end
    end

    desc "auth COMMAND", "Authentication commands"
    subcommand "auth", Commands::Auth

    desc "apps COMMAND", "Apps management commands"
    subcommand "apps", Commands::Apps
    desc "orgs COMMAND", "Organization management commands"
    subcommand "orgs", Commands::Orgs

    desc "projects COMMAND", "Project management commands"
    subcommand "projects", Commands::Projects

    desc "services COMMAND", "Service management commands"
    subcommand "services", Commands::Services

    desc "builds COMMAND", "Build management commands"
    subcommand "builds", Commands::Builds

    # Shortcut for auth:login
    desc "login", "Authenticate with nctl (alias for auth:login)"
    def login
      Commands::Auth.start(["login"] + build_option_args)
    end

    # Shortcut for auth:whoami
    desc "whoami", "Show current user (alias for auth:whoami)"
    def whoami
      Commands::Auth.start(["whoami"] + build_option_args)
    end

    # Shortcut for auth:logout
    desc "logout", "Log out from nctl (alias for auth:logout)"
    def logout
      Commands::Auth.start(["logout"] + build_option_args)
    end

    # Logs command
    desc "logs", "Show logs for an app"
    method_option :tail, aliases: "-t", type: :boolean, default: false, desc: "Stream logs continuously"
    method_option :lines, aliases: "-n", type: :numeric, default: 100, desc: "Number of lines to show"
    def logs
      setup_options
      app_ref = resolve_app
      @nctl.logs(app_ref, tail: options[:tail], lines: options[:lines])
    end

    # Exec command
    desc "exec [-- COMMAND]", "Run command in app container"
    def exec(*args)
      setup_options
      app_ref = resolve_app
      if args.empty?
        Output.error("No command specified. Usage: deploio exec -a APP -- COMMAND")
        exit 1
      end
      @nctl.exec_command(app_ref, args)
    end
    map "run" => :exec

    private

    def build_option_args
      args = []
      args << "--dry-run" if options[:dry_run]
      args << "--no-color" if options[:no_color]
      args << "--app" << options[:app] if options[:app]
      args << "--org" << options[:org] if options[:org]
      args
    end
  end
end
