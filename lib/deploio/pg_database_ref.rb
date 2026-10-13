# frozen_string_literal: true

require "did_you_mean"

module Deploio
  class PgDatabaseRef
    attr_reader :project_name, :database_name

    def initialize(input, available_databases: {})
      @input = input.to_s
      if available_databases.key?(@input)
        match = available_databases[@input]
        @project_name = match[:project_name]
        @database_name = match[:database_name]
      else
        raise_not_found_error(@input, available_databases.keys)
      end
    end

    def full_name = "#{project_name}-#{database_name}"
    def to_s = full_name

    def ==(other)
      other.is_a?(self.class) && project_name == other.project_name && database_name == other.database_name
    end

    private

    def raise_not_found_error(input, available_database_names)
      message = "Database not found: '#{input}'"
      suggestions = DidYouMean::SpellChecker.new(dictionary: available_database_names).correct(input) unless available_database_names.empty?
      unless suggestions.nil? || suggestions.empty?
        message += "\n\nDid you mean?"
        suggestions.each { |suggestion| message += "\n  #{suggestion}" }
      end
      message += "\n\nRun 'deploio pg' to see available Postgres databases."
      raise Deploio::PgDatabaseNotFoundError, message
    end
  end
end
