# frozen_string_literal: true

module Deploio
  # Backups for the dedicated tier (kind: Postgres), where we own the whole
  # database server and reach it over SSH
  # The nameing is confusing, but this is how Nine names them and how the resources appear, so prefer to stay
  # consistent with that
  class PostgresBackups
    DEFAULT_EXTENSION = ".zst"

    def initialize(data:, dry_run: false)
      @data = data || {}
      @dry_run = dry_run
    end

    def capture
      cmd = ["ssh", "dbadmin@#{fqdn}", "sudo nine-postgresql-backup"]
      Output.command(cmd.join(" "))
      system(*cmd) unless @dry_run
    end

    def download(destination:, db_name: nil)
      name = resolve_db_name(db_name)

      cmd = ["rsync", "-avz", "dbadmin@#{fqdn}:~/backup/postgresql/latest/customer/#{name}/#{name}.zst", destination]
      Output.command(cmd.join(" "))
      system(*cmd) unless @dry_run
    end

    private

    def resolve_db_name(db_name)
      if databases.empty?
        raise Deploio::Error, "No databases found in PostgreSQL instance; cannot download backup."
      elsif databases.size > 1 && db_name.nil?
        raise Deploio::Error,
          "Multiple databases found in PostgreSQL instance\n" \
          "Databases: #{databases.join(", ")}\n" \
          "Please specify the database name using the --db_name option."
      end

      db_name || databases.first
    end

    def databases
      @databases ||= (@data.dig("status", "atProvider", "databases")&.keys || []).reject { |db| db.strip.empty? }
    end

    def fqdn
      value = @data.dig("status", "atProvider", "fqdn")
      raise Deploio::Error, "Database FQDN not found; cannot reach the database server." if value.nil? || value.empty?

      value
    end
  end
end
