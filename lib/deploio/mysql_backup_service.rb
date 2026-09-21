# frozen_string_literal: true

module Deploio
  class MysqlBackupService < BackupService
    private

    def database_type = "MySQL"

    def backup_command = "nine-mysql-backup"

    def backup_directory = "mysql"

    def backup_download_command = "deploio ms backups download #{@name}"
  end
end
