# frozen_string_literal: true

require "json"
require "open3"

module Deploio
  # Read-only S3 access via rclone, used to fetch economy-tier (PostgresDatabase)
  # backups from the bucket Nine writes them to.
  #
  # Only `lsjson` and `copyto <remote> <local>` are ever issued. No mutating
  # rclone verb belongs in this class.
  class RcloneClient
    # rclone reads remote config from RCLONE_CONFIG_<REMOTE>_<KEY> env vars, which
    # keeps credentials out of argv (visible to any process via `ps`).
    REMOTE = "DEPLOIO"

    attr_reader :dry_run

    def initialize(endpoint:, access_key:, secret_key:, dry_run: false)
      @endpoint = endpoint
      @access_key = access_key
      @secret_key = secret_key
      @dry_run = dry_run
    end

    def check_requirements
      check_rclone_installed
    end

    # @return [Array<Hash>] entries with "Name", "Size" and "ModTime" keys
    def list(bucket)
      output = capture("lsjson", remote_path(bucket))
      return [] if output.nil? || output.empty?

      data = JSON.parse(output)
      data.is_a?(Array) ? data : []
    rescue JSON::ParserError
      []
    end

    def download(bucket, object, destination)
      run("copyto", remote_path(bucket, object), destination, "--progress", "--stats-one-line")
    end

    private

    # --s3-no-check-bucket skips the HeadBucket call, which the read-only bucket
    # user is not permitted to make.
    def build_command(args)
      ["rclone", *args.map(&:to_s), "--s3-no-check-bucket"]
    end

    def remote_path(bucket, object = nil)
      object ? "#{REMOTE}:#{bucket}/#{object}" : "#{REMOTE}:#{bucket}"
    end

    def env
      {
        "RCLONE_CONFIG_#{REMOTE}_TYPE" => "s3",
        "RCLONE_CONFIG_#{REMOTE}_PROVIDER" => "Other",
        "RCLONE_CONFIG_#{REMOTE}_ENDPOINT" => @endpoint,
        "RCLONE_CONFIG_#{REMOTE}_ACCESS_KEY_ID" => @access_key,
        "RCLONE_CONFIG_#{REMOTE}_SECRET_ACCESS_KEY" => @secret_key
      }
    end

    # Runs rclone and captures stdout. Used for lsjson. Raises on failure.
    def capture(*args)
      cmd = build_command(args)
      if dry_run
        Output.command(cmd.join(" "))
        return ""
      end

      puts "> #{cmd.join(" ")}" if ENV["DEPLOIO_DEBUG"]
      stdout, stderr, status = Open3.capture3(env, *cmd)
      unless status.success?
        raise Deploio::RcloneError, "rclone command failed: #{stderr}"
      end

      stdout
    end

    # Runs rclone with output to terminal so transfer progress streams live.
    def run(*args)
      cmd = build_command(args)
      Output.command(cmd.join(" "))
      return true if dry_run

      unless system(env, *cmd)
        raise Deploio::RcloneError, "rclone command failed: #{cmd.join(" ")}"
      end

      true
    end

    def check_rclone_installed
      _stdout, _stderr, status = Open3.capture3("rclone", "version")
      return if status.success?

      raise Deploio::RcloneError,
        "rclone not found. Please install it: brew install rclone"
    rescue Errno::ENOENT
      raise Deploio::RcloneError,
        "rclone not found. Please install it: brew install rclone"
    end
  end
end
