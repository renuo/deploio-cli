# frozen_string_literal: true

require "thor"

require_relative "deploio/version"
require_relative "deploio/utils"
require_relative "deploio/output"
require_relative "deploio/app_ref"
require_relative "deploio/pg_database_ref"
require_relative "deploio/nctl_client"
require_relative "deploio/app_resolver"
require_relative "deploio/pg_database_resolver"
require_relative "deploio/shared_options"
require_relative "deploio/cli"

module Deploio
  class Error < StandardError; end
  class AppNotFoundError < Error; end
  class PgDatabaseNotFoundError < Error; end
  class NctlError < Error; end
end
