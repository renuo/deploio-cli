# frozen_string_literal: true

require_relative "../price_fetcher"

module Deploio
  module Commands
    class Projects < Thor
      include SharedOptions

      namespace "projects"

      class_option :json, type: :boolean, default: false, desc: "Output as JSON"

      default_task :list

      desc "list", "List all projects"
      method_option :chf, type: :boolean, default: false,
        desc: "Show estimated total price (CHF) for each project with breakdown"
      def list
        setup_options
        raw_projects = @nctl.get_projects

        if options[:json]
          puts JSON.pretty_generate(raw_projects)
          return
        end

        if raw_projects.empty?
          Output.warning("No projects found") unless merged_options[:dry_run]
          return
        end

        current_org = @nctl.current_org
        show_price = merged_options[:chf]

        if show_price
          display_projects_with_breakdown(raw_projects, current_org)
        else
          display_projects_simple(raw_projects, current_org)
        end
      end

      private

      def display_projects_simple(raw_projects, current_org)
        rows = raw_projects.map do |project|
          metadata = project["metadata"] || {}
          spec = project["spec"] || {}
          labels = metadata["labels"] || {}
          namespace = metadata["namespace"] || ""
          name = metadata["name"] || ""

          display_name = compute_display_name(spec, labels, name, namespace)

          [
            presence(name),
            presence(display_name, default: ""),
            project_from_namespace(namespace, current_org)
          ]
        end

        Output.table(rows, headers: ["PROJECT", "DISPLAY NAME", "ORGANIZATION"])
      end

      def display_projects_with_breakdown(raw_projects, current_org)
        price_fetcher = PriceFetcher.new
        all_apps = @nctl.get_all_apps
        all_services = @nctl.get_all_services

        # Group apps and services by project
        apps_by_project = all_apps.group_by { |a| a.dig("metadata", "namespace") }
        services_by_project = all_services.group_by { |s| s.dig("metadata", "namespace") }

        groups = {}
        grand_total = 0

        raw_projects.sort_by { |p| p.dig("metadata", "name") || "" }.each do |project|
          metadata = project["metadata"] || {}
          spec = project["spec"] || {}
          labels = metadata["labels"] || {}
          name = metadata["name"] || ""

          display_name = compute_display_name(spec, labels, name, metadata["namespace"] || "")
          project_label = display_name.empty? ? name : display_name

          project_apps = apps_by_project[name] || []
          project_services = services_by_project[name] || []

          # Skip projects with no apps or services
          next if project_apps.empty? && project_services.empty?

          rows = []
          project_total = 0

          # Add apps
          project_apps.sort_by { |a| a.dig("metadata", "name") || "" }.each do |app|
            app_name = app.dig("metadata", "name") || "-"
            app_spec = app["spec"] || {}
            for_provider = app_spec["forProvider"] || {}
            config = for_provider["config"] || {}
            status = app["status"] || {}
            at_provider = status["atProvider"] || {}

            size = config["size"] || "micro"
            replicas = at_provider["replicas"] || for_provider["replicas"] || 1

            price = price_fetcher.price_for_app(app) || 0
            project_total += price

            size_info = replicas.to_i > 1 ? "#{size} ×#{replicas}" : size
            rows << [project_label, app_name, "app", size_info, format_price(price)]
          end

          # Add services
          project_services.sort_by { |s| [s["_type"] || "", s.dig("metadata", "name") || ""] }.each do |service|
            service_name = service.dig("metadata", "name") || "-"
            service_type = service["_type"] || "-"
            service_spec = service["spec"] || {}

            price = price_fetcher.price_for_service(service_type, service_spec) || 0
            project_total += price

            size_info = service_size_info(service_type, service_spec)
            rows << [project_label, service_name, service_type, size_info, format_price(price)]
          end

          # Add subtotal row
          rows << [project_label, "SUBTOTAL", "", "", format_price(project_total)]
          grand_total += project_total

          groups[project_label] = rows
        end

        if groups.empty?
          Output.warning("No apps or services found")
          return
        end

        Output.grouped_table(groups, headers: %w[PROJECT NAME TYPE SIZE PRICE])
        puts
        puts "Grand Total: CHF #{grand_total}/mo"
      end

      def service_size_info(type, spec)
        for_provider = spec["forProvider"] || {}

        case type
        when "postgres", "mysql"
          for_provider["machineType"] || for_provider["singleDBMachineType"] || "-"
        when "keyvaluestore"
          for_provider["memorySize"] || "-"
        else
          "-"
        end
      end

      def format_price(price)
        price > 0 ? "CHF #{price}/mo" : "-"
      end

      private

      def compute_display_name(spec, _labels, name, namespace)
        # Use displayName from spec if available (enriched from table output)
        return spec["displayName"] if spec["displayName"] && !spec["displayName"].empty?

        # Fallback: strip namespace prefix from name
        # e.g., "n10518-mytextur" -> "mytextur"
        name.delete_prefix("#{namespace}-")
      end

      def presence(value, default: "-")
        (value.nil? || value.to_s.empty?) ? default : value
      end

      def project_from_namespace(namespace, current_org)
        if current_org && namespace == current_org
          "#{namespace} (current)"
        else
          namespace
        end
      end
    end
  end
end
