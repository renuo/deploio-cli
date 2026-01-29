# frozen_string_literal: true

require_relative "../price_fetcher"

module Deploio
  module Commands
    class Services < Thor
      include SharedOptions

      namespace "services"

      class_option :json, type: :boolean, default: false, desc: "Output as JSON"

      default_task :list

      desc "list", "List services (all or filtered by project)"
      method_option :project, aliases: "-p", type: :string,
        desc: "Filter by project name"
      method_option :url, aliases: "-u", type: :boolean, default: false,
        desc: "Show connection URL for each service (requires --project)"
      method_option :connected_apps, aliases: "-c", type: :boolean, default: false,
        desc: "Show apps connected to each service (requires --project)"
      method_option :chf, type: :boolean, default: false,
        desc: "Show estimated price (CHF) for each service"
      def list
        setup_options

        validate_project_required_options!

        project = merged_options[:project] ? resolve_project(merged_options[:project]) : nil
        all_services = @nctl.get_all_services(project: project)

        if options[:json]
          puts JSON.pretty_generate(all_services)
          return
        end

        if all_services.empty?
          msg = project ? "No services found in project #{merged_options[:project]}" : "No services found"
          Output.warning(msg) unless merged_options[:dry_run]
          return
        end

        show_url = merged_options[:url]
        show_connected_apps = merged_options[:connected_apps]
        show_price = merged_options[:chf]
        current_org = @nctl.current_org

        # Pre-fetch apps and their env vars if we need to show connected apps
        apps_by_project = {}
        if show_connected_apps
          all_services.map { |s| s.dig("metadata", "namespace") }.uniq.each do |ns|
            apps_by_project[ns] = @nctl.get_apps_by_project(ns)
          end
        end

        # Initialize price fetcher if needed
        price_fetcher = PriceFetcher.new if show_price

        rows = all_services.map do |service|
          metadata = service["metadata"] || {}
          status = service["status"] || {}
          spec = service["spec"] || {}
          conditions = status["conditions"] || []
          ready_condition = conditions.find { |c| c["type"] == "Ready" }

          namespace = metadata["namespace"] || ""
          name = metadata["name"] || ""
          type = service["_type"] || "-"

          row = [
            short_service_name(namespace, name, current_org),
            project_from_namespace(namespace, current_org),
            type,
            presence(ready_condition&.dig("status"))
          ]

          if show_price
            price = price_fetcher.price_for_service(type, spec)
            row << price_fetcher.format_price(price)
          end

          # Get URL if needed (for display or for connected apps search)
          url = nil
          if show_url || show_connected_apps
            url = @nctl.get_service_connection_string(type, name, project: namespace)
          end

          row << presence(url) if show_url

          if show_connected_apps
            connected = find_connected_apps(apps_by_project[namespace] || [], url)
            row << (connected.empty? ? "-" : connected.join(", "))
          end

          row
        end

        headers = %w[SERVICE PROJECT TYPE READY]
        headers << "PRICE" if show_price
        headers << "URL" if show_url
        headers << "CONNECTED APPS" if show_connected_apps
        Output.table(rows, headers: headers)
      end

      private

      def validate_project_required_options!
        options_requiring_project = []
        options_requiring_project << "--url" if merged_options[:url]
        options_requiring_project << "--connected-apps" if merged_options[:connected_apps]

        return if options_requiring_project.empty? || merged_options[:project]

        Output.error("The #{options_requiring_project.join(" and ")} option(s) require --project to be specified")
        Output.info("Fetching this data for all services is too slow. Please filter by project first.")
        Output.info("Example: deploio services -p myproject #{options_requiring_project.first}")
        exit 1
      end

      def find_connected_apps(apps, service_url)
        return [] if service_url.nil? || service_url.empty?

        apps.filter_map do |app|
          app_name = app.dig("metadata", "name")
          env_vars = app.dig("spec", "forProvider", "config", "env") || []

          # Check if any env var value contains the service URL (or a recognizable part of it)
          connected = env_vars.any? do |env|
            value = env["value"].to_s
            next false if value.empty?

            # Match the service URL or its host part
            value.include?(service_url) || url_host_matches?(value, service_url)
          end

          app_name if connected
        end
      end

      def url_host_matches?(env_value, service_url)
        # Extract host from service URL and check if it appears in the env value
        # This handles cases where the env var might have a slightly different URL format
        service_host = extract_host(service_url)
        return false if service_host.nil?

        env_value.include?(service_host)
      end

      def extract_host(url)
        # Extract host from URLs like:
        # postgres://user:pass@host.example.com/db
        # rediss://:token@host.example.com:6379
        # mysql://user:pass@host.example.com:3306/db
        match = url.match(%r{://[^/]*@([^/:]+)})
        match&.[](1)
      end

      def presence(value, default: "-")
        return default if value.nil? || value.to_s.empty?

        value.to_s
      end

      def short_service_name(namespace, name, current_org)
        project = project_from_namespace(namespace, current_org)
        "#{project}-#{name}"
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
