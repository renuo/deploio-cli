# frozen_string_literal: true

require_relative "base_dashboard"

module Deploio
  module TUI
    class RatatuiDashboard
      include BaseDashboard

      def initialize
        @show_org_popup = false
        @org_selection = 0
        @tui = nil
        initialize_state
      end

      def run
        refresh_data

        RatatuiRuby.run do |tui|
          @tui = tui

          loop do
            break unless @running

            render
            handle_event(@tui.poll_event(timeout: 500))
          end
        end
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
          @tui.text_span(content: " DEPLOIO ", style: @tui.style(fg: :cyan, modifiers: [:bold])),
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
            text: "-" * area.width,
            style: @tui.style(fg: :dark_gray)
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
        items = filtered_apps.map.with_index do |app, idx|
          icon = app[:ready] ? "*" : "o"
          icon_style = @tui.style(fg: app[:ready] ? :green : :red)
          name = truncate(app[:display_name], area.width - 8)

          if idx == @selected_app_index
            @tui.text_line(spans: [
              @tui.text_span(content: " > ", style: @tui.style(fg: :cyan)),
              @tui.text_span(content: name, style: @tui.style(modifiers: [:bold])),
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

        list = @tui.list(
          items: items,
          block: @tui.block(
            title: " Apps ",
            borders: [:right],
            border_style: @tui.style(fg: :dark_gray)
          )
        )

        frame.render_widget(list, area)
      end

      def render_info_panel(frame, area)
        app = selected_app
        width = area.width - 2

        lines = if app
          build_info_lines(app, width)
        else
          [@tui.text_line(spans: [
            @tui.text_span(content: " No app selected", style: @tui.style(fg: :dark_gray))
          ])]
        end

        frame.render_widget(
          @tui.paragraph(text: lines),
          area
        )
      end

      def build_info_lines(app, width)
        lines = []

        # Title
        lines << @tui.text_line(spans: [
          @tui.text_span(
            content: " #{truncate(app[:display_name], width)}",
            style: @tui.style(modifiers: [:bold])
          )
        ])
        lines << @tui.text_line(spans: [@tui.text_span(content: "")])

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
            lines << text_line("   #{truncate(host, width - 5)}")
          end
        end

        lines
      end

      def text_line(content)
        @tui.text_line(spans: [@tui.text_span(content: content)])
      end

      def render_footer(frame, area)
        frame.render_widget(
          @tui.paragraph(
            text: " j/k:select  o:switch org  r:refresh  q:quit",
            style: @tui.style(fg: :dark_gray)
          ),
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
              @tui.text_span(content: display, style: @tui.style(modifiers: [:bold]))
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
        else
          handle_main_event(event)
        end
      end

      def handle_main_event(event)
        case event
        in {type: :key, code: "q"} | {type: :key, code: "c", modifiers: ["ctrl"]}
          @running = false
        in {type: :key, code: "j"} | {type: :key, code: "down"}
          move_selection_down
        in {type: :key, code: "k"} | {type: :key, code: "up"}
          move_selection_up
        in {type: :key, code: "o"}
          open_org_popup
        in {type: :key, code: "r"}
          refresh_data
        else
          nil
        end
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
