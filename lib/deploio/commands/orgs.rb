# frozen_string_literal: true

module Deploio
  module Commands
    class Orgs < Thor
      include SharedOptions

      namespace "orgs"

      class_option :json, type: :boolean, default: false, desc: "Output as JSON"

      default_task :list

      desc "list", "List all organizations"
      def list
        setup_options
        raw_orgs = @nctl.get_orgs

        if options[:json]
          puts JSON.pretty_generate(raw_orgs)
          return
        end

        if raw_orgs.empty?
          Output.warning("No organizations found") unless merged_options[:dry_run]
          return
        end

        rows = raw_orgs.map do |org|
          current_marker = org["current"] ? "*" : ""
          [
            current_marker,
            presence(org["name"])
          ]
        end

        Output.table(rows, headers: ["", "ORGANIZATION"])
      end

      desc "set ORG_NAME", "Set the current organization"
      def set(org_name)
        setup_options
        @nctl.set_org(org_name)
        Output.success("Switched to organization #{org_name}")
      end

      private

      def presence(value, default: "-")
        (value.nil? || value.to_s.empty?) ? default : value
      end
    end
  end
end
