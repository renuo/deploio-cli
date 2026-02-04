module Deploio
  module Commands
    class PostgreSQLBackups < Thor
      include SharedOptions

      namespace "pg:backups"

      desc "capture NAME", "Capture a new backup for the specified PostgreSQL database"
      def capture(name)
        setup_options
        resolver = PgDatabaseResolver.new(nctl_client: @nctl)
        db_ref = resolver.resolve(database_name: name)
        data = @nctl.get_pg_database(db_ref)
        kind = data["kind"] || ""

        unless kind == "Postgres" || @nctl.dry_run
          Output.error("Backups can only be captured for PostgreSQL databases. (shared dbs are not supported)")
          exit 1
        end

        fqdn = data.dig("status", "atProvider", "fqdn")
        if fqdn.nil? || fqdn.empty?
          Output.error("Database FQDN not found; cannot capture backup.")
          exit 1
        end

        cmd = ["ssh", "dbadmin@#{fqdn}", "sudo nine-postgresql-backup"]
        Output.command(cmd.join(" "))
        system(*cmd) unless @nctl.dry_run
      end

      desc "download NAME [--output destination_path]", "Download the latest backup for the specified PostgreSQL database instance"
      method_option :output, type: :string, desc: "Output file path (defaults to current directory with auto-generated name)"
      method_option :db_name, type: :string, desc: "If there are multiple DBs, specify which one to download the backup for", default: nil
      def download(name)
        destination = options[:output] || "./#{name}-latest-backup.zst"

        setup_options
        resolver = PgDatabaseResolver.new(nctl_client: @nctl)
        db_ref = resolver.resolve(database_name: name)
        data = @nctl.get_pg_database(db_ref)
        kind = data["kind"] || ""

        unless kind == "Postgres" || @nctl.dry_run
          Output.error("Backups can only be downloaded for PostgreSQL databases. (shared dbs are not supported)")
          exit 1
        end

        databases = data.dig("status", "atProvider", "databases")&.keys || []
        databases.reject! { |db| db.strip.empty? }
        if databases.empty?
          Output.error("No databases found in PostgreSQL instance; cannot download backup.")
          exit 1
        elsif databases.size > 1 && options[:db_name].nil?
          p databases
          Output.error("Multiple databases found in PostgreSQL instance")
          Output.error("Databases: #{databases.join(", ")}")
          Output.error("Please specify the database name using the --db_name option.")
          exit 1
        end

        db_name = options[:db_name] || databases.first

        fqdn = data.dig("status", "atProvider", "fqdn")
        if fqdn.nil? || fqdn.empty?
          Output.error("Database FQDN not found; cannot download backup.")
          exit 1
        end

        cmd = ["rsync", "-avz", "dbadmin@#{fqdn}:~/backup/postgresql/latest/customer/#{db_name}/#{db_name}.zst", destination]
        Output.command(cmd.join(" "))
        system(*cmd) unless @nctl.dry_run
      end
    end
  end
end
