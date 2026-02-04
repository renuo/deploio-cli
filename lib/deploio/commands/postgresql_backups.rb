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
    end
  end
end
