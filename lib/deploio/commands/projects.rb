# frozen_string_literal: true

module Deploio
  module Commands
    class Projects < Thor
      include SharedOptions

      namespace "projects"

      class_option :json, type: :boolean, default: false, desc: "Output as JSON"

      default_task :list

      desc "list", "List all projects"
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
