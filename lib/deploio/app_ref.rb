# frozen_string_literal: true

require 'did_you_mean'

# AppRef represents a reference to a deploio application.
module Deploio
  class AppRef
    attr_reader :project_name, :app_name

    # The input is given in the format "<project>-<app>"
    def initialize(input, available_apps: {})
      @input = input.to_s
      parse_from_available_apps(available_apps)
    end

    def full_name
      "#{project_name}-#{app_name}"
    end

    def to_s
      full_name
    end

    def ==(other)
      return false unless other.is_a?(AppRef)

      project_name == other.project_name && app_name == other.app_name
    end

    private

    def parse_from_available_apps(available_apps)
      if available_apps.key?(@input)
        match = available_apps[@input]
        @project_name = match[:project_name]
        @app_name = match[:app_name]
        return
      end

      # If available_apps provided but no match, raise error with suggestions
      raise_not_found_error(@input, available_apps.keys) unless available_apps.empty?

      raise_not_found_error(@input, [])
    end

    def raise_not_found_error(input, available_app_names)
      message = "App not found: '#{input}'"

      suggestions = suggest_similar(input, available_app_names)
      unless suggestions.empty?
        message += "\n\nDid you mean?"
        suggestions.each { |s| message += "\n  #{s}" }
      end

      message += "\n\nRun 'deploio apps' to see available apps."

      raise Deploio::AppNotFoundError, message
    end

    def suggest_similar(input, dictionary)
      return [] if dictionary.empty?

      spell_checker = DidYouMean::SpellChecker.new(dictionary: dictionary)
      spell_checker.correct(input)
    end
  end
end
