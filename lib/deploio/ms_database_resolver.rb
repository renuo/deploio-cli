# frozen_string_literal: true

module Deploio
  class MsDatabaseResolver < DatabaseResolver
    private

    def fetch_databases
      nctl.get_all_ms_databases
    end

    def database_ref
      MsDatabaseRef
    end
  end
end
