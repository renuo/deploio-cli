# frozen_string_literal: true

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
      def list
        setup_options

        if merged_options[:url] && !merged_options[:project]
          Output.error("The --url option requires --project to be specified")
          Output.info("Fetching URLs for all services is too slow. Please filter by project first.")
          Output.info("Example: deploio services -p myproject --url")
          exit 1
        end

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
        current_org = @nctl.current_org
        rows = all_services.map do |service|
          metadata = service["metadata"] || {}
          status = service["status"] || {}
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

          if show_url
            url = @nctl.get_service_connection_string(type, name, project: namespace)
            row << presence(url)
          end

          row
        end

        headers = %w[SERVICE PROJECT TYPE READY]
        headers << "URL" if show_url
        Output.table(rows, headers: headers)
      end

      private

      def resolve_project(project)
        current_org = @nctl.current_org
        # Don't prepend org if:
        # - No org context
        # - Project already contains a hyphen (already qualified)
        # - Project equals the org name (special case for default project)
        if current_org && !project.include?("-") && project != current_org
          "#{current_org}-#{project}"
        else
          project
        end
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
