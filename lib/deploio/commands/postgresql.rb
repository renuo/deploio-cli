module Deploio
  module Commands
    class PostgreSQL < Thor
      include SharedOptions

      namespace "pg"

      class_option :json, type: :boolean, default: false, desc: "Output as JSON"

      default_task :list

      desc "list", "List all PostgreSQL databases"
      def list
        setup_options
        raw_dbs = @nctl.get_all_pg_databases

        if options[:json]
          puts JSON.pretty_generate(raw_dbs)
          return
        end

        if raw_dbs.empty?
          Output.warning("No PostgreSQL databases found") unless merged_options[:dry_run]
          return
        end

        resolver = AppResolver.new(nctl_client: @nctl)

        rows = raw_dbs.map do |pg|
          kind = pg["kind"] || ""
          metadata = pg["metadata"] || {}
          spec = pg["spec"] || {}
          for_provider = spec["forProvider"] || {}
          version = for_provider["version"]
          namespace = metadata["namespace"] || ""
          name = metadata["name"] || ""

          [
            resolver.short_name_for(namespace, name),
            project_from_namespace(namespace, resolver.current_org),
            presence(kind, default: "-"),
            presence(version, default: "?")
          ]
        end

        Output.table(rows, headers: ["NAME", "PROJECT", "KIND", "VERSION"])
      end

      private

      def presence(value, default: "-")
        (value.nil? || value.to_s.empty?) ? default : value
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
