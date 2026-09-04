# frozen_string_literal: true

module Deploio
  class MysqlBackupService
    DEFAULT_EXTENSION = ".zst"

    def initialize(data:, name: nil, dry_run: false)
      @data = data || {}
      @name = name
      @dry_run = dry_run
    end

    def default_destination = "./#{@name}-latest-backup#{DEFAULT_EXTENSION}"

    def backups
      raise Deploio::UnsupportedBackupOperationError,
            "Listing backups is not yet supported for dedicated MySQL instances; Feel free to implement it!\n" \
              "Use 'deploio ms backups download #{@name}' to fetch it."
    end

    def capture
      cmd = ["ssh", "dbadmin@#{fqdn}", "sudo nine-mysql-backup"]
      Output.command(cmd.join(" "))
      system(*cmd) unless @dry_run
    end

    def download(destination:, db_name: nil)
      name = resolve_db_name(db_name)

      cmd = ["rsync", "-av", "dbadmin@#{fqdn}:~/backup/mysql/latest/customer/#{name}/#{name}.zst", destination]
      Output.command(cmd.join(" "))
      system(*cmd) unless @dry_run

      nil
    end

    private

    def resolve_db_name(db_name)
      if databases.empty?
        raise Deploio::Error, "No databases found in MySQL instance; cannot download backup."
      elsif databases.size > 1 && db_name.nil?
        raise Deploio::Error,
              "Multiple databases found in MySQL instance\n" \
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
