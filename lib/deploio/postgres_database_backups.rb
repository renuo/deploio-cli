# frozen_string_literal: true

module Deploio
  # Backups for the economy tier (kind: PostgresDatabase), where the database
  # lives on a shared server we have no access to.
  # The naming is confusing, but this is how Nine names them and how the resources appear, so prefer to stay
  # consistent with that
  class PostgresDatabaseBackups
    DEFAULT_EXTENSION = ".sql.zst"

    BACKUP_SCHEDULE_LABEL = "DatabaseBackupSchedule"

    def initialize(db_ref:, data:, nctl_client:, rclone_client_factory: nil)
      @db_ref = db_ref
      @data = data || {}
      @nctl = nctl_client
      @rclone_client_factory = rclone_client_factory || method(:build_rclone_client)
    end

    def backups
      @backups ||= begin
        entries = rclone.list(bucket_name)
        entries = entries.select { |e| own_backup?(e["Name"].to_s) }
        entries.sort_by { |e| e["ModTime"].to_s }.reverse
      end
    end

    def latest
      backups.first
    end

    def download(destination:)
      backup = latest
      unless backup
        raise Deploio::Error, "No backups found for '#{@db_ref.full_name}' in bucket '#{bucket_name}'."
      end

      rclone.download(bucket_name, backup["Name"], destination)
      backup
    end

    private

    def own_backup?(object_name)
      return true if instance_name.empty?

      object_name.start_with?("PostgresDatabase-#{instance_name}-")
    end

    def instance_name
      @instance_name ||= @data.dig("status", "atProvider", "name").to_s
    end

    def bucket_name
      bucket.dig("metadata", "name")
    end

    # The PostgresDatabase resource holds no reference to its backup bucket and
    # nctl exposes no databasebackupschedule resource, so we match from the
    # bucket side: the schedule-owned bucket named after this database.
    def bucket
      @bucket ||= begin
        candidates = @nctl.get_services_by_type("bucket", project: @db_ref.project_name).select do |bucket|
          backup_bucket_for_database?(bucket)
        end

        if candidates.empty?
          raise Deploio::Error,
            "No backup bucket found for '#{@db_ref.full_name}'. " \
            "Check that backups are enabled for this database (spec.forProvider.backupSchedule)."
        end

        candidates.first
      end
    end

    def backup_bucket_for_database?(bucket)
      metadata = bucket["metadata"] || {}
      labels = metadata["labels"] || {}
      return false unless labels["nine.ch/controllerKind"] == BACKUP_SCHEDULE_LABEL

      metadata["name"].to_s.match?(/\Apostgresdatabase-#{Regexp.escape(@db_ref.database_name)}-[0-9a-f]{7}\z/)
    end

    def rclone
      @rclone ||= @rclone_client_factory.call
    end

    def build_rclone_client
      endpoint = bucket.dig("status", "atProvider", "endpoint")
      if endpoint.nil? || endpoint.to_s.empty?
        raise Deploio::Error, "Backup bucket '#{bucket_name}' has no endpoint; cannot access backups."
      end

      client = RcloneClient.new(
        endpoint: "https://#{endpoint}",
        access_key: @nctl.get_bucket_user_access_key(bucket_name, project: @db_ref.project_name),
        secret_key: @nctl.get_bucket_user_secret_key(bucket_name, project: @db_ref.project_name),
        dry_run: @nctl.dry_run
      )
      client.check_requirements unless @nctl.dry_run
      client
    end
  end
end
