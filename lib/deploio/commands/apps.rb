# frozen_string_literal: true

require_relative "../price_fetcher"

module Deploio
  module Commands
    class Apps < Thor
      include SharedOptions

      namespace "apps"

      class_option :json, type: :boolean, default: false, desc: "Output as JSON"

      default_task :list

      desc "list", "List apps (all or filtered by project)"
      method_option :project, aliases: "-p", type: :string,
        desc: "Filter by project name"
      method_option :chf, type: :boolean, default: false,
        desc: "Show estimated price (CHF) for each app"
      def list
        setup_options
        project = merged_options[:project] ? resolve_project(merged_options[:project]) : nil
        raw_apps = project ? @nctl.get_apps_by_project(project) : @nctl.get_all_apps

        if options[:json]
          puts JSON.pretty_generate(raw_apps)
          return
        end

        if raw_apps.empty?
          msg = project ? "No apps found in project #{merged_options[:project]}" : "No apps found"
          Output.warning(msg) unless merged_options[:dry_run]
          return
        end

        resolver = AppResolver.new(nctl_client: @nctl)
        show_price = merged_options[:chf]
        price_fetcher = PriceFetcher.new if show_price

        rows = raw_apps.map do |app|
          metadata = app["metadata"] || {}
          spec = app["spec"] || {}
          for_provider = spec["forProvider"] || {}
          git = for_provider["git"] || {}
          config = for_provider["config"] || {}
          namespace = metadata["namespace"] || ""
          name = metadata["name"] || ""

          row = [
            resolver.short_name_for(namespace, name),
            project_from_namespace(namespace, resolver.current_org),
            presence(config["size"], default: "micro"),
            presence(git["revision"])
          ]

          if show_price
            price = price_fetcher.price_for_app(app)
            row << price_fetcher.format_price(price)
          end

          row
        end

        headers = %w[APP PROJECT SIZE REVISION]
        headers << "PRICE" if show_price
        Output.table(rows, headers: headers)
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

        default_url = at_provider["defaultURL"]
        default_url_display = default_url ? Output.link(default_url) : "-"

        Output.table([
          ["Ready", presence(ready_condition&.dig("status"))],
          ["Synced", presence(synced_condition&.dig("status"))],
          ["Default URL", default_url_display],
          ["Latest Build", presence(at_provider["latestBuild"])],
          ["Latest Release", presence(at_provider["latestRelease"])]
        ])

        puts

        hosts = for_provider["hosts"] || []
        if hosts.any?
          Output.header("Hosts")
          Output.list(hosts.map { |h| Output.link(h, "https://#{h}") })
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
