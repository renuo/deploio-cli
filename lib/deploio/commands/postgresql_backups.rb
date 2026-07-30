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
        db_ref, data = load_database(name)

        case data["kind"]
        when DEDICATED_KIND
          PostgresBackups.new(data: data, dry_run: @nctl.dry_run).capture
        when ECONOMY_KIND
          raise Deploio::Error,
            "'#{db_ref.full_name}' is an economy-tier database. Those are backed up automatically " \
            "on their configured schedule and cannot be captured manually.\n" \
            "Use 'deploio pg backups list #{name}' to see the available backups."
        else
          raise Deploio::Error, unsupported_kind_message(data["kind"])
        end
      rescue Deploio::Error => e
        Output.error(e.message)
        exit 1
      end

      desc "list NAME", "List the available backups for the specified PostgreSQL database"
      def list(name)
        db_ref, data = load_database(name)

        case data["kind"]
        when ECONOMY_KIND
          list_economy_backups(db_ref, data)
        when DEDICATED_KIND
          raise Deploio::Error,
            "Listing backups is not yet supported for dedicated PostgreSQL instances; only the latest " \
            "backup is kept on the server. Feel free to implement it!\n" \
            "Use 'deploio pg backups download #{name}' to fetch it."
        else
          raise Deploio::Error, unsupported_kind_message(data["kind"])
        end
      rescue Deploio::Error => e
        Output.error(e.message)
        exit 1
      end

      desc "download NAME [--output destination_path]", "Download the latest backup for the specified PostgreSQL database instance"
      method_option :output, type: :string, desc: "Output file path (defaults to current directory with auto-generated name)"
      method_option :db_name, type: :string, desc: "If there are multiple DBs, specify which one to download the backup for", default: nil
      def download(name)
        db_ref, data = load_database(name)

        case data["kind"]
        when DEDICATED_KIND
          PostgresBackups.new(data: data, dry_run: @nctl.dry_run).download(
            destination: destination_for(name, PostgresBackups::DEFAULT_EXTENSION),
            db_name: merged_options[:db_name]
          )
        when ECONOMY_KIND
          download_economy_backup(db_ref, data, name)
        else
          raise Deploio::Error, unsupported_kind_message(data["kind"])
        end
      rescue Deploio::Error => e
        Output.error(e.message)
        exit 1
      end

      private

      def list_economy_backups(db_ref, data)
        backups = economy_backups(db_ref, data).backups
        if backups.empty?
          Output.warning("No backups found for '#{db_ref.full_name}'")
          return
        end

        rows = backups.map do |backup|
          [format_time(backup["ModTime"]), format_size(backup["Size"]), backup["Name"]]
        end
        Output.table(rows, headers: ["DATE", "SIZE", "NAME"])
      end

      def download_economy_backup(db_ref, data, name)
        destination = destination_for(name, PostgresDatabaseBackups::DEFAULT_EXTENSION)
        backup = economy_backups(db_ref, data).download(destination: destination)
        Output.success("Downloaded backup from #{format_time(backup["ModTime"])} to #{destination}")
      end

      def economy_backups(db_ref, data)
        PostgresDatabaseBackups.new(db_ref: db_ref, data: data, nctl_client: @nctl)
      end

      def load_database(name)
        setup_options
        resolver = PgDatabaseResolver.new(nctl_client: @nctl)
        db_ref = resolver.resolve(database_name: name)
        data = @nctl.get_pg_database(db_ref)
        raise Deploio::Error, "Could not read database '#{db_ref.full_name}'." if data.nil?

        [db_ref, data]
      end

      def destination_for(name, extension)
        merged_options[:output] || "./#{name}-latest-backup#{extension}"
      end

      def unsupported_kind_message(kind)
        "Backups are not supported for databases of kind '#{kind}'."
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
