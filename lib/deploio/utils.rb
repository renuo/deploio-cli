module Deploio
  module Utils

    #  fetches the git remote of origin in the current directory
    # This is used in different places to auto-detect the app based on the current git remote ala heroku.
    def self.detect_git_remote
      stdout, _stderr, status = Open3.capture3('git', 'remote', 'get-url', 'origin')
      status.success? ? stdout.strip : nil
    rescue Errno::ENOENT
      nil
    end
  end
end
