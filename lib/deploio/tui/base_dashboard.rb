# frozen_string_literal: true

require "json"
require "open3"

module Deploio
  module TUI
    # Base module providing shared logic for all TUI implementations.
    # Handles data fetching, state management, and common operations.
    module BaseDashboard
      # State management
      attr_accessor :current_org, :apps_list, :selected_app_index,
        :main_view_mode, :org_popup_open, :log_buffer,
        :orgs_list, :selected_org_index, :filter_text,
        :running, :last_refresh, :error_message

      REFRESH_INTERVAL = 30 # seconds

      def initialize_state
        @nctl = NctlClient.new
        @current_org = nil
        @apps_list = []
        @orgs_list = []
        @selected_app_index = 0
        @selected_org_index = 0
        @main_view_mode = :info # :info or :logs
        @org_popup_open = false
        @log_buffer = []
        @filter_text = ""
        @running = true
        @last_refresh = Time.now - REFRESH_INTERVAL # Force initial refresh
        @error_message = nil
      end

      # Data fetching methods

      def fetch_orgs
        @orgs_list = @nctl.get_orgs
        @current_org = @orgs_list.find { |o| o["current"] }&.fetch("name", nil)
        @selected_org_index = @orgs_list.index { |o| o["current"] } || 0
        @orgs_list
      rescue Deploio::NctlError => e
        @error_message = "Failed to fetch orgs: #{e.message}"
        []
      end

      def fetch_apps
        raw_apps = @nctl.get_all_apps
        @apps_list = raw_apps.map { |app| parse_app_data(app) }
        @selected_app_index = 0 if @selected_app_index >= @apps_list.size
        @apps_list
      rescue Deploio::NctlError => e
        @error_message = "Failed to fetch apps: #{e.message}"
        []
      end

      def fetch_app_info(app)
        return {} unless app

        app_ref = build_app_ref(app)
        @nctl.get_app(app_ref)
      rescue Deploio::NctlError => e
        @error_message = "Failed to fetch app info: #{e.message}"
        {}
      end

      def capture_logs(app, lines: 50)
        return [] unless app

        app_ref = build_app_ref(app)
        output = capture_logs_output(app_ref, lines: lines)
        parse_log_lines(output)
      rescue => e
        @error_message = "Failed to fetch logs: #{e.message}"
        []
      end

      def switch_org(org_name)
        @nctl.set_org(org_name)
        @nctl.instance_variable_set(:@all_apps, nil) # Clear cached apps
        refresh_data
      rescue Deploio::NctlError => e
        @error_message = "Failed to switch org: #{e.message}"
      end

      # State management methods

      def selected_app
        filtered_apps[@selected_app_index]
      end

      def filtered_apps
        return @apps_list if @filter_text.empty?

        @apps_list.select { |app| app[:display_name].downcase.include?(@filter_text.downcase) }
      end

      def move_selection_up
        @selected_app_index = [0, @selected_app_index - 1].max
      end

      def move_selection_down
        max_index = [0, filtered_apps.size - 1].max
        @selected_app_index = [@selected_app_index + 1, max_index].min
      end

      def move_org_selection_up
        @selected_org_index = [0, @selected_org_index - 1].max
      end

      def move_org_selection_down
        max_index = [0, @orgs_list.size - 1].max
        @selected_org_index = [@selected_org_index + 1, max_index].min
      end

      def toggle_view_mode
        @main_view_mode = (@main_view_mode == :info) ? :logs : :info
        @log_buffer = capture_logs(selected_app) if @main_view_mode == :logs
      end

      def toggle_org_popup
        @org_popup_open = !@org_popup_open
        fetch_orgs if @org_popup_open
      end

      def select_current_org
        return unless @org_popup_open && @orgs_list[@selected_org_index]

        org_name = @orgs_list[@selected_org_index]["name"]
        switch_org(org_name)
        @org_popup_open = false
      end

      def refresh_data
        fetch_orgs
        fetch_apps
        @log_buffer = capture_logs(selected_app) if @main_view_mode == :logs
        @last_refresh = Time.now
        @error_message = nil
      end

      def should_auto_refresh?
        Time.now - @last_refresh >= REFRESH_INTERVAL
      end

      def quit
        @running = false
      end

      # App data parsing

      def parse_app_data(app)
        metadata = app["metadata"] || {}
        spec = app["spec"] || {}
        status = app["status"] || {}
        for_provider = spec["forProvider"] || {}
        git = for_provider["git"] || {}
        config = for_provider["config"] || {}
        at_provider = status["atProvider"] || {}

        namespace = metadata["namespace"] || ""
        name = metadata["name"] || ""

        # Determine ready status
        conditions = status["conditions"] || []
        ready_condition = conditions.find { |c| c["type"] == "Ready" }
        is_ready = ready_condition&.dig("status") == "True"

        # Build display name (strip org prefix if present)
        display_name = if @current_org && namespace.start_with?("#{@current_org}-")
          project = namespace.delete_prefix("#{@current_org}-")
          "#{project}-#{name}"
        else
          "#{namespace}-#{name}"
        end

        {
          namespace: namespace,
          name: name,
          display_name: display_name,
          ready: is_ready,
          size: config["size"] || "micro",
          replicas: for_provider["replicas"] || 1,
          git_url: git["url"],
          git_revision: git["revision"],
          default_url: at_provider["defaultURL"],
          latest_build: at_provider["latestBuild"],
          latest_release: at_provider["latestRelease"],
          hosts: for_provider["hosts"] || [],
          raw: app
        }
      end

      def parse_detailed_app_info(data)
        metadata = data["metadata"] || {}
        spec = data["spec"] || {}
        status = data["status"] || {}
        for_provider = spec["forProvider"] || {}
        git = for_provider["git"] || {}
        config = for_provider["config"] || {}
        at_provider = status["atProvider"] || {}

        conditions = status["conditions"] || []
        ready_condition = conditions.find { |c| c["type"] == "Ready" }
        synced_condition = conditions.find { |c| c["type"] == "Synced" }

        {
          name: metadata["name"],
          namespace: metadata["namespace"],
          size: config["size"] || "micro",
          replicas: for_provider["replicas"] || 1,
          port: config["port"] || 8080,
          ready: ready_condition&.dig("status"),
          synced: synced_condition&.dig("status"),
          default_url: at_provider["defaultURL"],
          latest_build: at_provider["latestBuild"],
          latest_release: at_provider["latestRelease"],
          git_url: git["url"],
          git_revision: git["revision"],
          git_sub_path: git["subPath"],
          hosts: for_provider["hosts"] || [],
          updated_at: metadata["creationTimestamp"]
        }
      end

      private

      def build_app_ref(app)
        AppRef.new(
          "#{app[:namespace]}-#{app[:name]}",
          available_apps: {
            "#{app[:namespace]}-#{app[:name]}" => {
              project_name: app[:namespace],
              app_name: app[:name]
            }
          }
        )
      end

      def capture_logs_output(app_ref, lines:)
        cmd = ["nctl", "logs", "app", app_ref.app_name,
          "--project", app_ref.project_name,
          "--lines=#{lines}"]
        stdout, _stderr, _status = Open3.capture3(*cmd)
        stdout
      end

      def parse_log_lines(output)
        return [] if output.nil? || output.empty?

        output.lines.map(&:chomp)
      end

      def time_ago_in_words(timestamp)
        return "-" if timestamp.nil?

        begin
          time = Time.parse(timestamp)
          seconds = Time.now - time
          case seconds
          when 0..59 then "just now"
          when 60..3599 then "#{(seconds / 60).to_i} minutes ago"
          when 3600..86399 then "#{(seconds / 3600).to_i} hours ago"
          else "#{(seconds / 86400).to_i} days ago"
          end
        rescue
          timestamp
        end
      end
    end
  end
end
