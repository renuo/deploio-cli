# frozen_string_literal: true

require "thor"

require_relative "deploio/version"
require_relative "deploio/utils"
require_relative "deploio/output"
require_relative "deploio/database_ref"
require_relative "deploio/database_resolver"
require_relative "deploio/backup_service"
require_relative "deploio/database_backup_service"
require_relative "deploio/app_ref"
require_relative "deploio/pg_database_ref"
require_relative "deploio/ms_database_ref"
require_relative "deploio/nctl_client"
require_relative "deploio/rclone_client"
require_relative "deploio/app_resolver"
require_relative "deploio/pg_database_resolver"
require_relative "deploio/postgres_backup_service"
require_relative "deploio/postgres_database_backup_service"
require_relative "deploio/ms_database_resolver"
require_relative "deploio/mysql_backup_service"
require_relative "deploio/mysql_database_backup_service"
require_relative "deploio/price_fetcher"
require_relative "deploio/shared_options"
require_relative "deploio/cli"

module Deploio
  class Error < StandardError; end
  class AppNotFoundError < Error; end
  class PgDatabaseNotFoundError < Error; end
  class MsDatabaseNotFoundError < Error; end
  class NctlError < Error; end
  class RcloneError < Error; end
  class UnsupportedBackupOperationError < Error; end
end
