# frozen_string_literal: true

module Deploio
  class PgDatabaseResolver < DatabaseResolver
    private

    def fetch_databases
      nctl.get_all_pg_databases
    end

    def database_ref
      PgDatabaseRef
    end
  end
end
