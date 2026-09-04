# frozen_string_literal: true

module Deploio
  class PostgresDatabaseBackupService < DatabaseBackupService
    private

    def resource_kind
      "PostgresDatabase"
    end

    def backup_command
      "pg"
    end
  end
end
