# frozen_string_literal: true

require 'tty-table'
require 'pastel'

# Utility module for formatted console output
module Deploio
  module Output
    class << self
      def color_enabled
        return @color_enabled if defined?(@color_enabled)

        @color_enabled = $stdout.tty?
      end

      def color_enabled=(value)
        @color_enabled = value
        @pastel = nil
      end

      def success(message)
        puts pastel.green("✓ #{message}")
      end

      def error(message)
        $stderr.puts pastel.red("✗ #{message}")
      end

      def warning(message)
        puts pastel.yellow("! #{message}")
      end

      def info(message)
        puts pastel.cyan("→ #{message}")
      end

      def command(cmd)
        puts pastel.bold("> #{cmd}")
      end

      def header(text)
        puts pastel.magenta.bold(text)
      end

      def table(rows, headers: nil)
        return if rows.empty?

        tty_table = headers ? TTY::Table.new(header: headers, rows: rows) : TTY::Table.new(rows: rows)
        puts tty_table.render(:unicode, padding: [0, 2, 0, 1], width: 10_000)
      end

      private

      def pastel
        @pastel ||= Pastel.new(enabled: color_enabled)
      end
    end
  end
end
