# frozen_string_literal: true

require "json"
require "open3"

module Deploio
  class NctlClient
    REQUIRED_VERSION = "1.10.0"

    attr_reader :dry_run

    def initialize(dry_run: false)
      @dry_run = dry_run
    end

    def check_requirements
      check_nctl_installed
      check_nctl_version
    end

    def logs(app_ref, tail: false, lines: 100)
      args = ["--lines=#{lines}"]
      args << "-f" if tail
      exec_passthrough("logs", "app", app_ref.app_name,
        "--project", app_ref.project_name,
        *args)
    end

    def build_logs(build_name, app_ref: nil, tail: false, lines: 5000)
      args = ["--lines=#{lines}"]
      args << "-f" if tail
      if app_ref
        args += ["--project", app_ref.project_name, "-a", app_ref.app_name]
      end
      exec_passthrough("logs", "build", *([build_name].compact), *args)
    end

    def exec_command(app_ref, command)
      exec_passthrough("exec", "app", app_ref.app_name,
        "--project", app_ref.project_name,
        "--", *command)
    end

    def get_all_apps
      @all_apps ||= begin
        output = capture("get", "apps", "-A", "-o", "json")
        return [] if output.nil? || output.empty?

        data = JSON.parse(output)
        data.is_a?(Array) ? data : (data["items"] || [])
      rescue JSON::ParserError
        []
      end
    end

    def get_app(app_ref)
      output = capture("get", "app", app_ref.app_name,
        "--project", app_ref.project_name,
        "-o", "json")
      return {} if output.nil? || output.empty?

      JSON.parse(output)
    rescue JSON::ParserError
      {}
    end

    def get_apps_by_project(project)
      output = capture("get", "apps", "--project", project, "-o", "json")
      return [] if output.nil? || output.empty?

      data = JSON.parse(output)
      data.is_a?(Array) ? data : (data["items"] || [])
    rescue JSON::ParserError
      []
    end

    def get_all_builds
      output = capture("get", "builds", "-A", "-o", "json")
      return [] if output.nil? || output.empty?

      data = JSON.parse(output)
      builds = data.is_a?(Array) ? data : (data["items"] || [])
      # Sort by creation timestamp descending (newest first)
      builds.sort_by { |b| b.dig("metadata", "creationTimestamp") || "" }.reverse
    rescue JSON::ParserError
      []
    end

    # @param app_ref [Deploio::AppRef]
    def get_builds(app_ref)
      output = capture("get", "builds",
        "--project", app_ref.project_name,
        "-a", app_ref.app_name,
        "-o", "json")
      return [] if output.nil? || output.empty?

      data = JSON.parse(output)
      builds = data.is_a?(Array) ? data : (data["items"] || [])
      # Sort by creation timestamp descending (newest first)
      builds.sort_by { |b| b.dig("metadata", "creationTimestamp") || "" }.reverse
    rescue JSON::ParserError
      []
    end

    def get_all_services(project: nil)
      service_types = %w[keyvaluestore postgres postgresdatabases mysql mysqldatabases opensearch bucket]
      all_services = []

      service_types.each do |type|
        services = get_services_by_type(type, project: project)
        services.each { |s| s["_type"] = type }
        all_services.concat(services)
      end

      all_services
    end

    def get_services_by_type(type, project: nil)
      args = ["get", type]
      if project
        args += ["--project", project]
      else
        args << "-A"
      end
      args += ["-o", "json"]

      output = capture(*args)
      return [] if output.nil? || output.empty?

      data = JSON.parse(output)
      data.is_a?(Array) ? data : (data["items"] || [])
    rescue JSON::ParserError
      []
    rescue Deploio::NctlError
      []
    end

    def get_service(type, name, project:)
      output = capture("get", type, name, "--project", project, "-o", "json")
      return nil if output.nil? || output.empty?

      JSON.parse(output)
    rescue JSON::ParserError
      nil
    rescue Deploio::NctlError
      nil
    end

    def get_service_connection_string(type, name, project:)
      case type
      when "postgres", "mysql", "postgresdatabases", "mysqldatabases"
        capture("get", type, name, "--project", project, "--print-connection-string").strip
      when "keyvaluestore"
        build_keyvaluestore_connection_string(name, project)
      when "opensearch"
        build_opensearch_connection_string(name, project)
      when "bucket"
        build_bucket_url(name, project)
      end
    rescue Deploio::NctlError
      nil
    end

    def get_projects
      output = capture("get", "projects", "-o", "json")
      return [] if output.nil? || output.empty?

      data = JSON.parse(output)
      projects = data.is_a?(Array) ? data : (data["items"] || [])

      display_names = get_project_display_names
      projects.each do |project|
        name = project.dig("metadata", "name")
        if display_names[name]
          project["spec"] ||= {}
          project["spec"]["displayName"] = display_names[name]
        end
      end

      projects
    rescue JSON::ParserError
      []
    end

    # Enrich with display names from table output (since JSON excludes spec.displayName)
    # TODO: https://github.com/ninech/nctl/pull/339
    def get_project_display_names
      output = capture("get", "projects")
      return {} if output.nil? || output.empty?

      display_names = {}
      output.each_line.drop(1).each do |line| # Skip header
        parts = line.strip.split(" ").map(&:strip)
        next if parts.length < 2

        project_name = parts[0]
        display_name = parts[1]
        display_names[project_name] = display_name unless display_name == "<none>"
      end
      display_names
    rescue Deploio::NctlError
      {}
    end

    def get_orgs
      output = capture("auth", "whoami")
      return [] if output.nil? || output.empty?

      parse_orgs_from_whoami(output)
    end

    def current_org
      get_orgs.find { |o| o["current"] }&.fetch("name", nil)
    end

    def parse_orgs_from_whoami(output)
      orgs = []
      in_orgs_section = false

      output.each_line do |line|
        if line.include?("Available Organizations:")
          in_orgs_section = true
          next
        end

        next unless in_orgs_section
        break if line.strip.empty? || line.start_with?("To switch")

        # Lines are either "*\torg_name" (current) or "\torg_name"
        current = line.start_with?("*")
        org_name = line.sub(/^\*?\t/, "").strip
        next if org_name.empty?

        orgs << {"name" => org_name, "current" => current}
      end

      orgs
    end

    def set_org(org_name)
      run("auth", "set-org", org_name)
    end

    def auth_login
      exec_passthrough("auth", "login")
    end

    def auth_logout
      run("auth", "logout")
    end

    def auth_whoami
      exec_passthrough("auth", "whoami")
    end

    private

    # Runs nctl command as subprocess with output to terminal. Used for
    # commands that modify state (create, delete) where we show output but don't need to parse it.
    def run(*args)
      cmd = build_command(args)
      Output.command(cmd.join(" "))
      if dry_run
        true
      else
        system(*cmd)
      end
    end

    # Replaces current process with nctl command. Used for interactive commands
    # (logs -f, exec, edit, auth) that need direct terminal access. Never returns.
    def exec_passthrough(*args)
      cmd = build_command(args)
      Output.command(cmd.join(" "))
      if dry_run
        true
      else
        exec(*cmd)
      end
    end

    # Runs nctl command and captures stdout. Used for commands that return data
    # (get apps, get projects) that needs to be parsed. Raises on failure.
    def capture(*args)
      cmd = build_command(args)
      if dry_run
        Output.command(cmd.join(" "))
        ""
      else
        stdout, stderr, status = Open3.capture3(*cmd)
        unless status.success?
          raise Deploio::NctlError, "nctl command failed: #{stderr}"
        end

        stdout
      end
    end

    def build_command(args)
      ["nctl"] + args.map(&:to_s)
    end

    def check_nctl_installed
      _stdout, _stderr, status = Open3.capture3("nctl", "--version")
      return if status.success?

      raise Deploio::NctlError,
        "nctl not found. Please install it: https://github.com/ninech/nctl"
    end

    def check_nctl_version
      stdout, _stderr, _status = Open3.capture3("nctl", "--version")
      version_match = stdout.match(/(\d+\.\d+\.\d+)/)
      return unless version_match

      version = version_match[1]
      return unless Gem::Version.new(version) < Gem::Version.new(REQUIRED_VERSION)

      raise Deploio::NctlError,
        "nctl version #{version} is too old. Need #{REQUIRED_VERSION}+. Run: brew upgrade nctl"
    end

    def build_keyvaluestore_connection_string(name, project)
      data = get_service("keyvaluestore", name, project: project)
      return nil unless data

      at_provider = data.dig("status", "atProvider") || {}
      fqdn = at_provider["fqdn"]
      return nil if fqdn.nil? || fqdn.empty?

      token = capture("get", "keyvaluestore", name, "--project", project, "--print-token").strip
      "rediss://:#{token}@#{fqdn}:6379"
    end

    def build_opensearch_connection_string(name, project)
      data = get_service("opensearch", name, project: project)
      return nil unless data

      at_provider = data.dig("status", "atProvider") || {}
      hosts = at_provider["hosts"] || []
      return nil if hosts.empty?

      user = capture("get", "opensearch", name, "--project", project, "--print-user").strip
      password = capture("get", "opensearch", name, "--project", project, "--print-password").strip
      host = hosts.first
      "https://#{user}:#{password}@#{host}"
    end

    def build_bucket_url(name, project)
      data = get_service("bucket", name, project: project)
      return nil unless data

      data.dig("status", "atProvider", "publicURL")
    end
  end
end
