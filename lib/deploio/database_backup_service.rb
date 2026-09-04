# frozen_string_literal: true

module Deploio
  class DatabaseBackupService
    DEFAULT_EXTENSION = ".sql.zst"
    BACKUP_SCHEDULE_LABEL = "DatabaseBackupSchedule"

    def initialize(
      db_ref:,
      data:,
      nctl_client:,
      name: nil,
      rclone_client_factory: nil
    )
      @db_ref = db_ref
      @data = data || {}
      @nctl = nctl_client
      @name = name || db_ref.full_name
      @rclone_client_factory = rclone_client_factory || method(:build_rclone_client)
    end

    def default_destination
      "./#{@name}-latest-backup#{DEFAULT_EXTENSION}"
    end

    # Nine takes these backups on a schedule and there is no way to trigger one.
    def capture
      raise Deploio::UnsupportedBackupOperationError,
        "'#{@db_ref.full_name}' is an economy-tier database. Those are backed up automatically " \
          "on their configured schedule and cannot be captured manually.\n" \
          "Use 'deploio #{backup_command} backups list #{@name}' to see the available backups."
    end

    def backups
      @backups ||= begin
        entries = rclone.list(bucket_name)
        entries = entries.select { |entry| own_backup?(entry["Name"].to_s) }
        entries.sort_by { |entry| entry["ModTime"].to_s }.reverse
      end
    end

    def download(destination:, db_name: nil)
      backup = backups.first

      unless backup
        raise Deploio::Error,
          "No backups found for '#{@db_ref.full_name}' in bucket '#{bucket_name}'."
      end

      rclone.download(bucket_name, backup["Name"], destination)
      backup
    end

    private

    def own_backup?(object_name)
      return true if instance_name.empty?

      object_name.start_with?("#{resource_kind}-#{instance_name}-")
    end

    def instance_name
      @instance_name ||= @data.dig("status", "atProvider", "name").to_s
    end

    def bucket_name
      bucket.dig("metadata", "name")
    end

    # The database resource holds no reference to its backup bucket.
    # Therefore, match the bucket by name for now.
    def bucket
      @bucket ||= begin
        candidates = @nctl
         .get_services_by_type("bucket", project: @db_ref.project_name)
         .select { |candidate| backup_bucket_for_database?(candidate) }

        if candidates.empty?
          raise Deploio::Error,
            "No backup bucket found for '#{@db_ref.full_name}'. " \
              "Check that backups are enabled for this database " \
              "(spec.forProvider.backupSchedule)."
        end

        candidates.first
      end
    end

    def backup_bucket_for_database?(bucket)
      metadata = bucket["metadata"] || {}
      labels = metadata["labels"] || {}

      return false unless labels["nine.ch/controllerKind"] == BACKUP_SCHEDULE_LABEL

      metadata["name"].to_s.match?(
        /\A#{resource_kind.downcase}-#{Regexp.escape(@db_ref.database_name)}-[0-9a-f]{7}\z/
      )
    end

    def rclone
      @rclone ||= @rclone_client_factory.call
    end

    def build_rclone_client
      endpoint = bucket.dig("status", "atProvider", "endpoint")

      if endpoint.nil? || endpoint.to_s.empty?
        raise Deploio::Error,
          "Backup bucket '#{bucket_name}' has no endpoint; cannot access backups."
      end

      client = RcloneClient.new(
        endpoint: "https://#{endpoint}",
        access_key: @nctl.get_bucket_user_access_key(
          bucket_name,
          project: @db_ref.project_name
        ),
        secret_key: @nctl.get_bucket_user_secret_key(
          bucket_name,
          project: @db_ref.project_name
        ),
        dry_run: @nctl.dry_run
      )

      client.check_requirements unless @nctl.dry_run
      client
    end

    def resource_kind
      raise NotImplementedError
    end

    def backup_command
      raise NotImplementedError
    end
  end
end
