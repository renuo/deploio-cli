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

        resolver = PgDatabaseResolver.new(nctl_client: @nctl)

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

      desc "info NAME", "Show PostgreSQL database details"
      def info(name)
        setup_options
        resolver = PgDatabaseResolver.new(nctl_client: @nctl)
        db_ref = resolver.resolve(database_name: name)
        data = @nctl.get_pg_database(db_ref)

        if options[:json]
          puts JSON.pretty_generate(data)
          return
        end

        kind = data["kind"]
        metadata = data["metadata"] || {}
        spec = data["spec"] || {}
        for_provider = spec["forProvider"] || {}
        status = data["status"] || {}
        at_provider = status["atProvider"] || {}

        Output.header("PostgreSQL Database: #{db_ref.full_name}")
        puts

        Output.header("General")
        Output.table([
          ["Name", presence(metadata["name"])],
          ["Project", presence(metadata["namespace"])],
          ["Kind", presence(kind, default: "-")],
          ["Version", presence(for_provider["version"], default: "?")],
          ["FQDN", presence(at_provider["fqdn"])],
          ["Size", presence(at_provider["size"], default: "-")]
        ])

        puts

        Output.header("Status")
        conditions = status["conditions"] || []
        ready_condition = conditions.find { |c| c["type"] == "Ready" }
        synced_condition = conditions.find { |c| c["type"] == "Synced" }

        Output.table([
          ["Ready", presence(ready_condition&.dig("status"))],
          ["Synced", presence(synced_condition&.dig("status"))]
        ])

        if for_provider["allowedCIDRs"].is_a?(Array)
          puts

          Output.header("Access")
          Output.table([
            ["Allowed CIDRs", for_provider["allowedCIDRs"].join(", ")]
          ])

          puts

          Output.header("SSH Keys")
          for_provider["sshKeys"].each do |key|
            puts "- #{key}"
          end
        end
      rescue Deploio::Error => e
        Output.error(e.message)
        exit 1
      end

      desc "backups COMMAND", "Manage PostgreSQL database backups"
      subcommand "backups", Commands::PostgreSQLBackups

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
