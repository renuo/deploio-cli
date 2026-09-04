# frozen_string_literal: true

module Deploio
  class MsDatabaseRef < DatabaseRef
    private

    def error_class
      Deploio::MsDatabaseNotFoundError
    end

    def command
      "ms"
    end

    def database_type
      "MySQL"
    end
  end
end
