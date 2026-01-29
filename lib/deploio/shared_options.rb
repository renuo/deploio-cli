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
        .merge(parent_options.to_h) { |_key, sub, par| par.nil? ? sub : par }
        .transform_keys(&:to_sym)
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
