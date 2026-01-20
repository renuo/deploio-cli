# frozen_string_literal: true


module Deploio
  class AppResolver
    attr_reader :nctl, :git_remote_url, :current_org

    def initialize(nctl_client:)
      @nctl = nctl_client
      @git_remote_url = Utils.detect_git_remote
      @current_org = @nctl.current_org
    end

    def resolve(app_name: nil)
      # 1. Explicit --app flag
      if app_name
        return AppRef.new(app_name, available_apps: available_apps_hash)
      end

      # 2. Match git remote against nctl apps
      if git_remote_url
        matches = find_apps_by_git_remote(git_remote_url)

        case matches.size
        when 0
          raise Deploio::AppNotFoundError,
                "No deploio apps found matching git remote: #{git_remote_url}\n" \
                "Use --app to specify the app explicitly.\n" \
                "Run 'deploio apps' to see available apps."
        when 1
          return build_app_ref_from_match(matches.first)
        else
          app_names = matches.map { |m| format_match(m) }
          raise Deploio::Error,
                "Multiple apps found for this repo. Use --app to specify which one:\n" \
                "#{app_names.map { |name| "  #{name}" }.join("\n")}"
        end
      end

      raise Deploio::Error,
            "No app specified. Use --app <project-app> or run from a git repo with a matching remote."
    end

    # Returns hash mapping app names -> {project_name:, app_name:}
    # Supports both full names (org-project-app) and short names (project-app)
    def available_apps_hash
      @available_apps_hash ||= begin
        hash = {}
        current_org = @nctl.current_org
        @nctl.get_all_apps.each do |app|
          metadata = app['metadata'] || {}
          project_name = metadata['namespace'] || ''
          app_name = metadata['name']
          full_name = "#{project_name}-#{app_name}"
          hash[full_name] = { project_name: project_name, app_name: app_name }

          # Also index by short name (without org prefix) for convenience
          if current_org && project_name.start_with?("#{current_org}-")
            project = project_name.delete_prefix("#{current_org}-")
            short_name = "#{project}-#{app_name}"
            hash[short_name] ||= { project_name: project_name, app_name: app_name }
          end
        end
        hash
      end
    rescue StandardError
      {}
    end

    def short_name_for(namespace, app_name)
      org = current_org
      if org && namespace.start_with?("#{org}-")
        project = namespace.delete_prefix("#{org}-")
        "#{project}-#{app_name}"
      else
        "#{namespace}-#{app_name}"
      end
    end

    private

    def find_apps_by_git_remote(git_url)
      normalized_url = normalize_git_url(git_url)
      @nctl.get_all_apps.select do |app|
        app_git_url = app.dig('spec', 'forProvider', 'git', 'url')
        normalize_git_url(app_git_url) == normalized_url
      end
    end

    def normalize_git_url(url)
      return nil if url.nil?

      url.strip
         .sub(/\.git$/, '')
         .sub(%r{^https://github\.com/}, 'git@github.com:')
         .downcase
    end

    def build_app_ref_from_match(match)
      metadata = match['metadata'] || {}
      namespace = metadata['namespace'] || ''
      name = metadata['name']
      AppRef.new("#{namespace}-#{name}", available_apps: available_apps_hash)
    end

    def format_match(match)
      metadata = match['metadata'] || {}
      namespace = metadata['namespace'] || ''
      name = metadata['name']
      short_name_for(namespace, name)
    end
  end
end
