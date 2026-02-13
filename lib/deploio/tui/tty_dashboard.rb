# frozen_string_literal: true

require_relative "minitui"
require_relative "base_dashboard"

module Deploio
  module TUI
    class TTYDashboard
      include BaseDashboard

      def initialize
        @show_org_popup = false
        @org_selection = 0
        @filter_mode = false
        @log_stream = nil
        @log_thread = nil
        initialize_state
      end

      def run
        refresh_data

        Minitui.run do |tui|
          @tui = tui

          loop do
            break unless @running

            render
            handle_event(tui.poll_event(timeout: 200))
          end
        end
      ensure
        stop_log_stream
      end

      private

      def render
        @tui.draw do |frame|
          area = frame.area

          # Main layout: header, separator, content, separator, footer
          header_area, sep1_area, content_area, sep2_area, footer_area = @tui.layout_split(
            area,
            direction: :vertical,
            constraints: [
              @tui.constraint_length(1),
              @tui.constraint_length(1),
              @tui.constraint_fill(1),
              @tui.constraint_length(1),
              @tui.constraint_length(1)
            ]
          )

          render_header(frame, header_area)
          render_separator(frame, sep1_area)
          render_content(frame, content_area)
          render_separator(frame, sep2_area)
          render_footer(frame, footer_area)

          render_org_popup(frame, area) if @show_org_popup
        end
      end

      def render_header(frame, area)
        org = @current_org || "?"
        text = [
          @tui.text_span(content: " DEPLOIO ", style: @tui.style(fg: :cyan, bold: true)),
          @tui.text_span(content: " " * [area.width - 26 - org.length, 1].max),
          @tui.text_span(content: "org: #{org}  [o] [q]")
        ]

        frame.render_widget(
          @tui.paragraph(text: @tui.text_line(spans: text)),
          area
        )
      end

      def render_separator(frame, area)
        frame.render_widget(
          @tui.paragraph(
            text: "\u2500" * area.width,
            style: @tui.style(dim: true)
          ),
          area
        )
      end

      def render_content(frame, area)
        left_area, right_area = @tui.layout_split(
          area,
          direction: :horizontal,
          constraints: [
            @tui.constraint_length(34),
            @tui.constraint_fill(1)
          ]
        )

        render_apps_list(frame, left_area)
        render_info_panel(frame, right_area)
      end

      def render_apps_list(frame, area)
        # Split area if filter is active
        if @filter_mode || !@filter_text.empty?
          filter_area, list_area = @tui.layout_split(
            area,
            direction: :vertical,
            constraints: [
              @tui.constraint_length(1),
              @tui.constraint_fill(1)
            ]
          )
          render_filter_input(frame, filter_area)
        else
          list_area = area
        end

        items = filtered_apps.map.with_index do |app, idx|
          icon = app[:ready] ? "*" : "o"
          icon_style = @tui.style(fg: app[:ready] ? :green : :red)
          name = truncate(app[:display_name], list_area.width - 8)

          if idx == @selected_app_index
            @tui.text_line(spans: [
              @tui.text_span(content: " > ", style: @tui.style(fg: :cyan)),
              @tui.text_span(content: name, style: @tui.style(bold: true)),
              @tui.text_span(content: " "),
              @tui.text_span(content: icon, style: icon_style)
            ])
          else
            @tui.text_line(spans: [
              @tui.text_span(content: "   "),
              @tui.text_span(content: name),
              @tui.text_span(content: " "),
              @tui.text_span(content: icon, style: icon_style)
            ])
          end
        end

        items = [@tui.text_line(spans: [
          @tui.text_span(content: "  (no apps)", style: @tui.style(dim: true))
        ])] if items.empty?

        list = @tui.list(
          items: items,
          block: @tui.block(
            borders: [:right],
            border_style: @tui.style(dim: true)
          )
        )

        frame.render_widget(list, list_area)
      end

      def render_filter_input(frame, area)
        cursor = @filter_mode ? "_" : ""
        text = @tui.text_line(spans: [
          @tui.text_span(content: " /", style: @tui.style(fg: :cyan)),
          @tui.text_span(content: @filter_text, style: @tui.style(fg: :cyan, bold: true)),
          @tui.text_span(content: cursor, style: @tui.style(fg: :cyan))
        ])

        frame.render_widget(@tui.paragraph(text: text), area)
      end

      def render_info_panel(frame, area)
        app = selected_app

        if @main_view_mode == :logs
          render_logs_panel(frame, area, app)
        else
          render_app_info(frame, area, app)
        end
      end

      def render_app_info(frame, area, app)
        width = area.width - 2

        lines = if app
          build_info_lines(app, width)
        else
          [@tui.text_line(spans: [
            @tui.text_span(content: " No app selected", style: @tui.style(dim: true))
          ])]
        end

        frame.render_widget(@tui.paragraph(text: lines), area)
      end

      def render_logs_panel(frame, area, app)
        width = area.width - 2

        unless app
          frame.render_widget(
            @tui.paragraph(text: " No app selected", style: @tui.style(dim: true)),
            area
          )
          return
        end

        # Header line
        lines = []
        lines << @tui.text_line(spans: [
          @tui.text_span(content: " Logs: ", style: @tui.style(bold: true)),
          @tui.text_span(content: app[:display_name], style: @tui.style(fg: :cyan))
        ])
        lines << text_line("")

        if @log_buffer.empty?
          lines << @tui.text_line(spans: [
            @tui.text_span(content: " (no logs)", style: @tui.style(dim: true))
          ])
        else
          # Show as many log lines as fit in the area
          available_height = area.height - 2
          start_idx = [0, @log_buffer.size - available_height].max

          @log_buffer[start_idx..].each do |log_line|
            lines << text_line(" #{truncate(log_line, width - 1)}")
          end
        end

        frame.render_widget(@tui.paragraph(text: lines), area)
      end

      def build_info_lines(app, width)
        lines = []

        # Title
        lines << @tui.text_line(spans: [
          @tui.text_span(
            content: " #{truncate(app[:display_name], width)}",
            style: @tui.style(bold: true)
          )
        ])
        lines << text_line("")

        # Status
        status_style = @tui.style(fg: app[:ready] ? :green : :red)
        status_text = app[:ready] ? "Ready" : "Down"
        lines << @tui.text_line(spans: [
          @tui.text_span(content: " Status:   "),
          @tui.text_span(content: status_text, style: status_style)
        ])

        lines << text_line(" Size:     #{app[:size] || "-"}")
        lines << text_line(" Replicas: #{app[:replicas] || "-"}")
        lines << text_line("")

        # Git info
        if app[:git_url]
          git = app[:git_url].sub(%r{.*[:/]}, "").sub(/\.git$/, "")
          lines << text_line(" Repo:     #{truncate(git, width - 11)}")
        end
        lines << text_line(" Branch:   #{app[:git_revision] || "-"}")
        lines << text_line("")

        # Build info
        lines << text_line(" Build:    #{truncate(app[:latest_build] || "-", width - 11)}")
        lines << text_line(" Release:  #{truncate(app[:latest_release] || "-", width - 11)}")

        # Hosts
        if app[:hosts]&.any?
          lines << text_line("")
          lines << text_line(" Hosts:")
          app[:hosts].first(3).each do |host|
            url = host.start_with?("http") ? host : "https://#{host}"
            lines << @tui.text_line(spans: [
              @tui.text_span(content: "   "),
              @tui.text_span(
                content: truncate(host, width - 5),
                style: @tui.style(fg: :cyan, underline: true, link: url)
              )
            ])
          end
        end

        lines
      end

      def text_line(content)
        @tui.text_line(spans: [@tui.text_span(content: content)])
      end

      def render_footer(frame, area)
        help_text = if @filter_mode
          " Type to filter, Enter:confirm, Esc:clear"
        elsif @main_view_mode == :logs
          " j/k:switch app  Esc:back to info  r:restart  q:quit  (streaming...)"
        elsif !@filter_text.empty?
          " j/k:select  l:logs  /:filter  Esc:clear  o:org  r:refresh  q:quit"
        else
          " j/k:select  l:logs  /:filter  o:switch org  r:refresh  q:quit"
        end

        frame.render_widget(
          @tui.paragraph(text: help_text, style: @tui.style(dim: true)),
          area
        )
      end

      def render_org_popup(frame, area)
        return if @orgs_list.empty?

        popup_w = [40, area.width - 10].min
        popup_h = [@orgs_list.size + 2, area.height - 6].min
        popup_x = (area.width - popup_w) / 2
        popup_y = (area.height - popup_h) / 2

        popup_area = @tui.rect(x: popup_x, y: popup_y, width: popup_w, height: popup_h)

        # Clear area
        frame.render_widget(@tui.clear, popup_area)

        # Build org list
        items = @orgs_list.map.with_index do |org, idx|
          name = org["name"]
          current = org["current"] ? " *" : ""
          display = truncate("#{name}#{current}", popup_w - 8)

          if idx == @org_selection
            @tui.text_line(spans: [
              @tui.text_span(content: " > ", style: @tui.style(fg: :cyan)),
              @tui.text_span(content: display, style: @tui.style(bold: true))
            ])
          else
            @tui.text_line(spans: [
              @tui.text_span(content: "   #{display}")
            ])
          end
        end

        list = @tui.list(
          items: items,
          block: @tui.block(
            title: " Switch Organization ",
            borders: [:all],
            border_style: @tui.style(fg: :cyan)
          )
        )

        frame.render_widget(list, popup_area)
      end

      def handle_event(event)
        return unless event

        if @show_org_popup
          handle_org_popup_event(event)
        elsif @filter_mode
          handle_filter_event(event)
        else
          handle_main_event(event)
        end
      end

      def handle_main_event(event)
        case event
        in {type: :key, code: "q"} | {type: :key, code: "c", modifiers: ["ctrl"]}
          stop_log_stream
          @running = false
        in {type: :key, code: "j"} | {type: :key, code: "down"}
          move_selection_down
          fetch_logs_if_needed
        in {type: :key, code: "k"} | {type: :key, code: "up"}
          move_selection_up
          fetch_logs_if_needed
        in {type: :key, code: "/"}
          @filter_mode = true
        in {type: :key, code: "escape"}
          handle_escape
        in {type: :key, code: "l"}
          enter_logs_mode
        in {type: :key, code: "o"}
          open_org_popup unless @main_view_mode == :logs
        in {type: :key, code: "r"}
          if @main_view_mode == :logs
            # Restart log stream
            @log_buffer = []
            start_log_stream(@current_log_app) if @current_log_app
          else
            refresh_data
          end
        else
          nil
        end
      end

      def enter_logs_mode
        return unless selected_app

        @main_view_mode = :logs
        @log_buffer = []
        @current_log_app = selected_app
        start_log_stream(selected_app)
      end

      def fetch_logs_if_needed
        return unless @main_view_mode == :logs && selected_app

        # If we switched apps while in logs mode, restart the stream
        if @current_log_app != selected_app
          stop_log_stream
          @log_buffer = []
          @current_log_app = selected_app
          start_log_stream(selected_app)
        end
      end

      def start_log_stream(app)
        stop_log_stream # Ensure any existing stream is stopped

        app_ref = build_app_ref(app)
        cmd = ["nctl", "logs", "app", app_ref.app_name,
               "--project", app_ref.project_name, "-f"]

        @log_stream = IO.popen(cmd, err: [:child, :out])
        @log_thread = Thread.new do
          @log_stream.each_line do |line|
            @log_buffer << line.chomp
            # Keep buffer size manageable
            @log_buffer.shift if @log_buffer.size > 500
          end
        rescue IOError
          # Stream closed, ignore
        end
      end

      def stop_log_stream
        if @log_stream
          Process.kill("TERM", @log_stream.pid) rescue nil
          @log_stream.close rescue nil
          @log_stream = nil
        end
        if @log_thread
          @log_thread.kill rescue nil
          @log_thread = nil
        end
      end

      def handle_escape
        if @main_view_mode == :logs
          stop_log_stream
          @main_view_mode = :info
          @log_buffer = []
          @current_log_app = nil
        elsif !@filter_text.empty?
          clear_filter
        end
      end

      def handle_filter_event(event)
        case event
        in {type: :key, code: "escape"}
          clear_filter
        in {type: :key, code: "enter"}
          @filter_mode = false
        in {type: :key, code: "backspace"}
          @filter_text = @filter_text[0..-2] if @filter_text.length > 0
          @selected_app_index = 0
        in {type: :key, code: c} if c.length == 1 && c =~ /[a-zA-Z0-9\-_\.]/
          @filter_text += c
          @selected_app_index = 0
        else
          nil
        end
      end

      def clear_filter
        @filter_text = ""
        @filter_mode = false
        @selected_app_index = 0
      end

      def handle_org_popup_event(event)
        case event
        in {type: :key, code: "q"} | {type: :key, code: "escape"}
          @show_org_popup = false
        in {type: :key, code: "j"} | {type: :key, code: "down"}
          @org_selection = [@orgs_list.size - 1, @org_selection + 1].min
        in {type: :key, code: "k"} | {type: :key, code: "up"}
          @org_selection = [0, @org_selection - 1].max
        in {type: :key, code: "enter"}
          select_org
        else
          nil
        end
      end

      def open_org_popup
        fetch_orgs
        @org_selection = @orgs_list.index { |o| o["current"] } || 0
        @show_org_popup = true
      end

      def select_org
        return if @orgs_list.empty?

        selected = @orgs_list[@org_selection]
        return unless selected

        @show_org_popup = false
        return if selected["current"]

        switch_org(selected["name"])
      end

      def truncate(s, max)
        s = s.to_s
        (s.length > max) ? "#{s[0, max - 1]}~" : s
      end
    end
  end
end
