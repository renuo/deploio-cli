# frozen_string_literal: true

module Deploio
  class PgDatabaseRef < DatabaseRef
    private

    def error_class
      Deploio::PgDatabaseNotFoundError
    end

    def command
      "pg"
    end

    def database_type
      "Postgres"
    end
  end
end
