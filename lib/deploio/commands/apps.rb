# frozen_string_literal: true

module Deploio
  module Commands
    class Apps < Thor
      include SharedOptions

      namespace "apps"

      class_option :json, type: :boolean, default: false, desc: "Output as JSON"

      default_task :list

      desc "list", "List all apps"
      def list
        setup_options
        raw_apps = @nctl.get_all_apps

        if options[:json]
          puts JSON.pretty_generate(raw_apps)
          return
        end

        if raw_apps.empty?
          Output.warning("No apps found") unless merged_options[:dry_run]
          return
        end

        resolver = AppResolver.new(nctl_client: @nctl)

        rows = raw_apps.map do |app|
          metadata = app["metadata"] || {}
          spec = app["spec"] || {}
          for_provider = spec["forProvider"] || {}
          git = for_provider["git"] || {}
          config = for_provider["config"] || {}
          namespace = metadata["namespace"] || ""
          name = metadata["name"] || ""

          [
            resolver.short_name_for(namespace, name),
            project_from_namespace(namespace, resolver.current_org),
            presence(config["size"], default: "micro"),
            presence(git["revision"])
          ]
        end

        Output.table(rows, headers: %w[APP PROJECT SIZE REVISION])
      end

      desc "info", "Show app details"
      def info
        setup_options
        app_ref = resolve_app
        data = @nctl.get_app(app_ref)

        if options[:json]
          puts JSON.pretty_generate(data)
          return
        end

        display_app_info(data, app_ref)
      end

      private

      def display_app_info(data, app_ref)
        metadata = data["metadata"] || {}
        spec = data["spec"] || {}
        status = data["status"] || {}
        for_provider = spec["forProvider"] || {}
        git = for_provider["git"] || {}
        config = for_provider["config"] || {}
        build_env = for_provider["buildEnv"] || []
        at_provider = status["atProvider"] || {}

        Output.header("App: #{app_ref.full_name}")
        puts

        Output.header("General")
        Output.table([
          ["Name", presence(metadata["name"])],
          ["Project", presence(metadata["namespace"])],
          ["Size", presence(config["size"], default: "micro")],
          ["Replicas", presence(for_provider["replicas"], default: "1")],
          ["Port", presence(config["port"], default: "8080")]
        ])

        puts

        Output.header("Status")
        conditions = status["conditions"] || []
        ready_condition = conditions.find { |c| c["type"] == "Ready" }
        synced_condition = conditions.find { |c| c["type"] == "Synced" }

        Output.table([
          ["Ready", presence(ready_condition&.dig("status"))],
          ["Synced", presence(synced_condition&.dig("status"))],
          ["Default URL", presence(at_provider["defaultURL"])],
          ["Latest Build", presence(at_provider["latestBuild"])],
          ["Latest Release", presence(at_provider["latestRelease"])]
        ])

        puts

        hosts = for_provider["hosts"] || []
        if hosts.any?
          Output.header("Hosts")
          Output.table(hosts.map { |h| [presence(h)] })
          puts
        end

        Output.header("Git")
        Output.table([
          ["Repository", presence(git["url"])],
          ["Revision", presence(git["revision"])],
          ["Sub Path", presence(git["subPath"])]
        ])
        puts

        if build_env.any? || for_provider["dockerfilePath"]
          Output.header("Build")
          rows = []
          rows << ["Dockerfile", presence(for_provider["dockerfilePath"])] if for_provider["dockerfilePath"]
          build_env.each do |env|
            rows << [env["name"], presence(env["value"], max_length: 60)]
          end
          Output.table(rows, headers: %w[SETTING VALUE]) if rows.any?
          puts
        end
      end

      def presence(value, default: "-", max_length: nil)
        return default if value.nil? || value.to_s.empty?

        str = value.to_s
        (max_length && str.length > max_length) ? "#{str[0, max_length - 3]}..." : str
      end

      def project_from_namespace(namespace, current_org)
        if current_org && namespace.start_with?("#{current_org}-")
          namespace.delete_prefix("#{current_org}-")
        else
          namespace
        end
      end
    end
  end
end
