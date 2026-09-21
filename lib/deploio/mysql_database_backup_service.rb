# frozen_string_literal: true

module Deploio
  class MysqlDatabaseBackupService < DatabaseBackupService
    private

    def resource_kind
      "MySQLDatabase"
    end

    def backup_command
      "ms"
    end
  end
end
