# frozen_string_literal: true

require "time"

module Deploio
  module Commands
    class Builds < Thor
      include SharedOptions

      namespace "builds"

      class_option :json, type: :boolean, default: false, desc: "Output as JSON"

      desc "list", "List builds (all or for a specific app)"
      def list
        setup_options

        if merged_options[:app]
          list_for_app
        else
          list_all
        end
      end

      desc "logs [BUILD_NAME]", "Show build logs"
      method_option :tail, aliases: "-t", type: :boolean, default: false, desc: "Stream logs continuously"
      method_option :lines, aliases: "-n", type: :numeric, default: 5000, desc: "Number of lines to show"
      def logs(build_name = nil)
        setup_options
        app_ref = merged_options[:app] ? resolve_app : nil
        @nctl.build_logs(build_name, app_ref: app_ref, tail: options[:tail], lines: options[:lines])
      end

      private

      def list_all
        raw_builds = @nctl.get_all_builds

        if options[:json]
          puts JSON.pretty_generate(raw_builds)
          return
        end

        if raw_builds.empty?
          Output.warning("No builds found") unless merged_options[:dry_run]
          return
        end

        resolver = AppResolver.new(nctl_client: @nctl)

        rows = raw_builds.map do |build|
          metadata = build["metadata"] || {}
          spec = build["spec"] || {}
          status = build["status"] || {}
          for_provider = spec["forProvider"] || {}
          git = for_provider["sourceConfig"]&.dig("git") || {}
          at_provider = status["atProvider"] || {}
          labels = metadata["labels"] || {}
          app_name = labels["application.apps.nine.ch/name"] || "-"
          namespace = metadata["namespace"] || ""

          [
            resolver.short_name_for(namespace, app_name),
            presence(metadata["name"]),
            format_status(at_provider["buildStatus"]),
            presence(git["revision"], max_length: 20),
            format_timestamp(metadata["creationTimestamp"])
          ]
        end

        Output.table(rows, headers: %w[APP BUILD STATUS REVISION CREATED])
      end

      def list_for_app
        app_ref = resolve_app
        raw_builds = @nctl.get_builds(app_ref)

        if options[:json]
          puts JSON.pretty_generate(raw_builds)
          return
        end

        if raw_builds.empty?
          Output.warning("No builds found for #{app_ref.full_name}") unless merged_options[:dry_run]
          return
        end

        rows = raw_builds.map do |build|
          metadata = build["metadata"] || {}
          spec = build["spec"] || {}
          status = build["status"] || {}
          for_provider = spec["forProvider"] || {}
          git = for_provider["sourceConfig"]&.dig("git") || {}
          at_provider = status["atProvider"] || {}

          [
            presence(metadata["name"]),
            format_status(at_provider["buildStatus"]),
            presence(git["revision"], max_length: 30),
            format_timestamp(metadata["creationTimestamp"])
          ]
        end

        Output.table(rows, headers: %w[BUILD STATUS REVISION CREATED])
      end

      def presence(value, default: "-", max_length: nil)
        return default if value.nil? || value.to_s.empty?

        str = value.to_s
        (max_length && str.length > max_length) ? "#{str[0, max_length - 3]}..." : str
      end

      def format_status(status)
        return "-" if status.nil? || status.to_s.empty?

        case status.downcase
        when "succeeded", "success"
          Output.color_enabled ? "\e[32m#{status}\e[0m" : status
        when "error", "failed"
          Output.color_enabled ? "\e[31m#{status}\e[0m" : status
        when "building", "running", "pending"
          Output.color_enabled ? "\e[33m#{status}\e[0m" : status
        else
          status
        end
      end

      def format_timestamp(timestamp)
        return "-" if timestamp.nil? || timestamp.to_s.empty?

        time = Time.parse(timestamp)
        time.strftime("%Y-%m-%d %H:%M")
      rescue ArgumentError
        timestamp
      end
    end
  end
end
