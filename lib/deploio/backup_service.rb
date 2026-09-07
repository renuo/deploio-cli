# frozen_string_literal: true

module Deploio
  class BackupService
    DEFAULT_EXTENSION = ".zst"

    # @param name [String] the name the user typed, used for hints in messages
    def initialize(data:, name: nil, dry_run: false)
      @data = data || {}
      @name = name
      @dry_run = dry_run
    end

    def default_destination = "./#{@name}-latest-backup#{DEFAULT_EXTENSION}"

    def backups
      raise Deploio::UnsupportedBackupOperationError,
            "Listing backups is not yet supported for dedicated #{database_type} instances; Feel free to implement it!\n" \
              "Use '#{backup_download_command}' to fetch it."
    end

    def capture
      cmd = ["ssh", "dbadmin@#{fqdn}", "sudo", backup_command]
      Output.command(cmd.join(" "))
      system(*cmd) unless @dry_run
    end

    def download(destination:, db_name: nil)
      name = resolve_db_name(db_name)

      cmd = [
        "rsync",
        "-av",
        "dbadmin@#{fqdn}:~/backup/#{backup_directory}/latest/customer/#{name}/#{name}.zst",
        destination
      ]

      Output.command(cmd.join(" "))
      system(*cmd) unless @dry_run

      nil
    end

    private

    def resolve_db_name(db_name)
      if databases.empty?
        raise Deploio::Error,
              "No databases found in #{database_type} instance; cannot download backup."
      elsif databases.size > 1 && db_name.nil?
        raise Deploio::Error,
              "Multiple databases found in #{database_type} instance\n" \
                "Databases: #{databases.join(", ")}\n" \
                "Please specify the database name using the --db_name option."
      end

      db_name || databases.first
    end

    def databases
      @databases ||= (
        @data.dig("status", "atProvider", "databases")&.keys || []
      ).reject { |db| db.strip.empty? }
    end

    def fqdn
      value = @data.dig("status", "atProvider", "fqdn")

      if value.nil? || value.empty?
        raise Deploio::Error,
              "Database FQDN not found; cannot reach the database server."
      end

      value
    end

    def database_type
      raise NotImplementedError
    end

    def backup_command
      raise NotImplementedError
    end

    def backup_directory
      raise NotImplementedError
    end

    def backup_download_command
      raise NotImplementedError
    end
  end
end
