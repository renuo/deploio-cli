module Deploio
  module BackupFormatting
    def self.format_size(bytes)
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
  end
end
