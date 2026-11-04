# frozen_string_literal: true

require "time"

module Deploio
  module BackupsHelper
    def format_size(bytes)
      bytes = bytes.to_i
      units = ["B", "KiB", "MiB", "GiB", "TiB"]
      index = 0
      size = bytes.to_f
      while size >= 1024 && index < units.size - 1
        size /= 1024
        index += 1
      end
      (index.zero? ? "#{bytes} B" : format("%.1f %s", size, units[index]))
    end

    def format_time(value)
      Time.parse(value.to_s).localtime.strftime("%Y-%m-%d %H:%M")
    rescue ArgumentError, TypeError
      value.to_s
    end
  end
end
