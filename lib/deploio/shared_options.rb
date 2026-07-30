# frozen_string_literal: true

require "open3"

module Deploio
  module SharedOptions
    def self.included(base)
      base.class_option :app, aliases: "-a", type: :string, desc: "App in <project>-<app> format"
      base.class_option :org, aliases: "-o", type: :string, desc: "Organization"
      base.class_option :dry_run, type: :boolean, default: false, desc: "Print commands without executing"
      base.class_option :no_color, type: :boolean, default: false, desc: "Disable colored output"

      base.define_singleton_method(:exit_on_failure?) { true }
    end

    private

    # Merges parent CLI options with subcommand options.
    # Parent options take precedence over subcommand defaults.
    def merged_options
      @merged_options ||= options
        .to_h
        .merge(parent_options.to_h) { |_key, sub, par| merge_option_value(sub, par) }
        .transform_keys(&:to_sym)
    end

    # Boolean flags default to false rather than nil, so a parent that simply
    # didn't get the flag is indistinguishable from one that had it disabled.
    # Treating them as "set anywhere wins" keeps flags like --dry-run working
    # when they are passed to a nested subcommand (e.g. `pg backups download`).
    def merge_option_value(sub, parent)
      return sub if parent.nil?
      return sub || parent if [true, false].include?(sub) || [true, false].include?(parent)

      parent
    end

    # Rebuilds the shared class options as CLI arguments so they survive being
    # handed to another Thor class. Thor's generated subcommand dispatch passes
    # the parent's option *values* along, which drops flags once subcommands are
    # nested two levels deep (e.g. `deploio pg backups download`).
    def forwarded_option_args
      args = []
      args << "--dry-run" if merged_options[:dry_run]
      args << "--no-color" if merged_options[:no_color]
      args << "--app" << merged_options[:app] if merged_options[:app]
      args << "--org" << merged_options[:org] if merged_options[:org]
      args
    end

    def setup_options
      Output.color_enabled = !merged_options[:no_color] && $stdout.tty?
      @nctl = NctlClient.new(dry_run: merged_options[:dry_run])
      @nctl.check_requirements unless merged_options[:dry_run]
    end

    # @return [Deploio::AppRef]
    def resolve_app
      resolver = AppResolver.new(nctl_client: @nctl)
      resolver.resolve(app_name: merged_options[:app])
    rescue Deploio::Error => e
      Output.error(e.message)
      exit 1
    end

    # Resolves a project name to its fully qualified form (org-project).
    # Users can type short names like "myproject" and this will prepend the org.
    # @param project [String] Project name (short or fully qualified)
    # @return [String] Fully qualified project name
    def resolve_project(project)
      current_org = @nctl.current_org
      return project unless current_org

      # Special case: project equals org name (default project)
      return project if project == current_org

      # Always prepend org to get fully qualified name
      "#{current_org}-#{project}"
    end
  end
end
