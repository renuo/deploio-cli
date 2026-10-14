# frozen_string_literal: true

require "did_you_mean"

module Deploio
  class PgDatabaseRef
    attr_reader :project_name, :database_name

    # The input is given in the format "<project>-<database>"
    def initialize(input, available_databases: {})
      @input = input.to_s
      parse_from_available_databases(available_databases)
    end

    def full_name
      "#{project_name}-#{database_name}"
    end

    def to_s
      full_name
    end

    def ==(other)
      return false unless other.is_a?(PgDatabaseRef)

      project_name == other.project_name && database_name == other.database_name
    end

    private

    def parse_from_available_databases(available_databases)
      if available_databases.key?(@input)
        match = available_databases[@input]
        @project_name = match[:project_name]
        @database_name = match[:database_name]
        return
      end

      # If available_databases provided but no match, raise error with suggestions
      raise_not_found_error(@input, available_databases.keys) unless available_databases.empty?

      raise_not_found_error(@input, [])
    end

    def raise_not_found_error(input, available_database_names)
      message = "Database not found: '#{input}'"

      suggestions = suggest_similar(input, available_database_names)
      unless suggestions.empty?
        message += "\n\nDid you mean?"
        suggestions.each { |s| message += "\n  #{s}" }
      end

      message += "\n\nRun 'deploio pg' to see available Postgres databases."

      raise Deploio::PgDatabaseNotFoundError, message
    end

    def suggest_similar(input, dictionary)
      return [] if dictionary.empty?

      spell_checker = DidYouMean::SpellChecker.new(dictionary: dictionary)
      spell_checker.correct(input)
    end
  end
end
