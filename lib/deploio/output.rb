# frozen_string_literal: true

require "tty-table"
require "pastel"

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
        warn pastel.red("✗ #{message}")
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

      # Create a clickable hyperlink using OSC 8 escape sequences
      # Supported by most modern terminal emulators (iTerm2, GNOME Terminal, Windows Terminal, etc.)
      def link(text, url = nil)
        return text unless color_enabled

        url ||= text.start_with?("http") ? text : "https://#{text}"
        "\e]8;;#{url}\e\\#{text}\e]8;;\e\\"
      end

      def table(rows, headers: nil)
        return if rows.empty?

        tty_table = headers ? TTY::Table.new(header: headers, rows: rows) : TTY::Table.new(rows: rows)
        puts tty_table.render(:unicode, padding: [0, 2, 0, 1], width: 10_000)
      end

      def list(items)
        items.each { |item| puts "  • #{item}" }
      end

      def grouped_table(groups, headers: nil)
        return if groups.empty?

        all_rows = groups.values.flatten(1)
        return if all_rows.empty?

        # Track which row indices should have separators after them (0-indexed)
        # The separator lambda receives the row index (0 = first data row)
        separator_after = []
        current_idx = 0
        groups.each_with_index do |(_, group_rows), group_idx|
          current_idx += group_rows.size
          # Add separator after last row of each group (except the last group)
          separator_after << (current_idx - 1) if group_idx < groups.size - 1
        end

        rows = groups.values.flatten(1)
        tty_table = headers ? TTY::Table.new(header: headers, rows: rows) : TTY::Table.new(rows: rows)

        output = tty_table.render(:unicode, padding: [0, 2, 0, 1], width: 10_000) do |renderer|
          # row_idx 0 = separator after header, then data row indices
          renderer.border.separator = ->(row_idx) { row_idx == 0 || separator_after.include?(row_idx - 1) }
        end

        puts output
      end

      private

      def pastel
        @pastel ||= Pastel.new(enabled: color_enabled)
      end
    end
  end
end
