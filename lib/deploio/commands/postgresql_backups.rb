require "time"

module Deploio
  module Commands
    class PostgreSQLBackups < Thor
      include SharedOptions

      namespace "pg:backups"

      DEDICATED_KIND = "Postgres"
      ECONOMY_KIND = "PostgresDatabase"

      desc "capture NAME", "Capture a new backup for the specified PostgreSQL database"
      def capture(name)
        backup_service_for(name).capture
      rescue Deploio::Error => e
        Output.error(e.message)
        exit 1
      end

      desc "list NAME", "List the available backups for the specified PostgreSQL database"
      def list(name)
        backups = backup_service_for(name).backups
        if backups.empty?
          Output.warning("No backups found for '#{name}'")
          return
        end

        rows = backups.map do |backup|
          [format_time(backup["ModTime"]), format_size(backup["Size"]), backup["Name"]]
        end
        Output.table(rows, headers: ["DATE", "SIZE", "NAME"])
      rescue Deploio::Error => e
        Output.error(e.message)
        exit 1
      end

      desc "download NAME [--output destination_path]", "Download the latest backup for the specified PostgreSQL database instance"
      method_option :output, type: :string, desc: "Output file path (defaults to current directory with auto-generated name)"
      method_option :db_name, type: :string, desc: "If there are multiple DBs, specify which one to download the backup for", default: nil
      def download(name)
        service = backup_service_for(name)
        destination = merged_options[:output] || service.default_destination
        backup = service.download(destination: destination, db_name: merged_options[:db_name])

        # Only the economy tier knows when its backup was taken.
        if backup
          Output.success("Downloaded backup from #{format_time(backup["ModTime"])} to #{destination}")
        else
          Output.success("Downloaded backup to #{destination}")
        end
      rescue Deploio::Error => e
        Output.error(e.message)
        exit 1
      end

      private

      def backup_service_for(name)
        setup_options
        resolver = PgDatabaseResolver.new(nctl_client: @nctl)
        db_ref = resolver.resolve(database_name: name)
        data = @nctl.get_pg_database(db_ref)
        raise Deploio::Error, "Could not read database '#{db_ref.full_name}'." if data.nil?

        case data["kind"]
        when DEDICATED_KIND
          PostgresBackupService.new(data: data, name: name, dry_run: @nctl.dry_run)
        when ECONOMY_KIND
          PostgresDatabaseBackupService.new(db_ref: db_ref, data: data, nctl_client: @nctl, name: name)
        else
          raise Deploio::UnsupportedBackupOperationError,
            "Backups are not supported for databases of kind '#{data["kind"]}'."
        end
      end

      def format_time(value)
        Time.parse(value.to_s).localtime.strftime("%Y-%m-%d %H:%M")
      rescue ArgumentError, TypeError
        value.to_s
      end

      def format_size(bytes)
        bytes = bytes.to_i
        units = ["B", "KiB", "MiB", "GiB", "TiB"]
        index = 0
        size = bytes.to_f
        while size >= 1024 && index < units.size - 1
          size /= 1024
          index += 1
        end
        (index.zero? ? "#{bytes} B" : format("%.1f %s", size, units[index]))
      end
    end
  end
end
