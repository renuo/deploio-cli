# frozen_string_literal: true

module Deploio
  # Backups for the dedicated tier (kind: Postgres), where we own the whole
  # database server and reach it over SSH
  # The naming is confusing, but this is how Nine names them and how the resources appear, so prefer to stay
  # consistent with that
  class PostgresBackupService < BackupService
    private

    def database_type = "PostgreSQL"

    def backup_command = "nine-postgresql-backup"

    def backup_directory = "postgresql"

    def backup_download_command = "deploio pg backups download #{@name}"
  end
end
