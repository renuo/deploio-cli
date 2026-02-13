# frozen_string_literal: true

require "io/console"

module Minitui
  # Color constants (accessible module-wide)
  COLORS = {
    black: 30, red: 31, green: 32, yellow: 33,
    blue: 34, magenta: 35, cyan: 36, white: 37,
    dark_gray: 90, light_red: 91, light_green: 92, light_yellow: 93,
    light_blue: 94, light_magenta: 95, light_cyan: 96, light_white: 97
  }.freeze

  BG_COLORS = COLORS.transform_values { |v| v + 10 }.freeze

  # Geometry: Rectangle representing a screen area
  Rect = Struct.new(:x, :y, :width, :height, keyword_init: true) do
    def self.zero
      new(x: 0, y: 0, width: 0, height: 0)
    end
  end

  # Layout constraints
  module Constraint
    Length = Struct.new(:value, keyword_init: true)
    Fill = Struct.new(:weight, keyword_init: true)
    Percentage = Struct.new(:value, keyword_init: true)
  end

  # Style for text rendering
  Style = Struct.new(:fg, :bg, :bold, :dim, :italic, :underline, :link, keyword_init: true) do
    def apply(text)
      codes = []
      codes << Minitui::COLORS[fg] if fg && Minitui::COLORS[fg]
      codes << Minitui::BG_COLORS[bg] if bg && Minitui::BG_COLORS[bg]
      codes << 1 if bold
      codes << 2 if dim
      codes << 3 if italic
      codes << 4 if underline

      result = text
      result = "\e[#{codes.join(";")}m#{result}\e[0m" unless codes.empty?
      result = "\e]8;;#{link}\e\\#{result}\e]8;;\e\\" if link
      result
    end
  end

  # Text span with content and style
  TextSpan = Struct.new(:content, :style, keyword_init: true) do
    def render
      style ? style.apply(content) : content
    end

    def visible_length
      content.to_s.length
    end
  end

  # Line of text spans
  TextLine = Struct.new(:spans, keyword_init: true) do
    def render
      spans.map(&:render).join
    end

    def visible_length
      spans.sum(&:visible_length)
    end
  end

  # Widgets
  module Widgets
    # Simple text paragraph
    class Paragraph
      attr_reader :text, :style

      def initialize(text:, style: nil)
        @text = text
        @style = style
      end

      def render_to_buffer(buffer, area)
        lines = case text
        when String
          [text]
        when TextLine
          [text]
        when Array
          text
        else
          [text.to_s]
        end

        lines.each_with_index do |line, idx|
          break if idx >= area.height

          if line.is_a?(TextLine)
            write_text_line(buffer, area.x, area.y + idx, line, area.width)
          else
            str = style ? style.apply(line.to_s) : line.to_s
            buffer.write_string(area.x, area.y + idx, str, style_to_hash(style))
          end
        end
      end

      private

      def write_text_line(buffer, x, y, text_line, max_width)
        current_x = x
        text_line.spans.each do |span|
          break if current_x >= x + max_width

          content = span.content.to_s
          remaining = x + max_width - current_x
          content = content[0, remaining] if content.length > remaining

          style_hash = style_to_hash(span.style)
          content.each_char do |c|
            buffer.set(current_x, y, c, style_hash)
            current_x += 1
          end
        end

        # Fill rest with spaces
        while current_x < x + max_width
          buffer.set(current_x, y, " ", nil)
          current_x += 1
        end
      end

      def style_to_hash(style)
        return nil unless style

        hash = {}
        hash[:fg] = COLORS[style.fg] if style.fg
        hash[:bg] = BG_COLORS[style.bg] if style.bg
        hash[:bold] = true if style.bold
        hash[:dim] = true if style.dim
        hash[:underline] = true if style.underline
        hash[:link] = style.link if style.link
        hash.empty? ? nil : hash
      end
    end

    # List widget with items
    class List
      attr_reader :items, :block

      def initialize(items:, block: nil)
        @items = items
        @block = block
      end

      def render_to_buffer(buffer, area)
        # Render block border if present
        content_area = if block
          block.render_to_buffer(buffer, area)
          block.inner_area(area)
        else
          area
        end

        # Render items
        items.each_with_index do |item, idx|
          break if idx >= content_area.height

          if item.is_a?(TextLine)
            write_text_line(buffer, content_area.x, content_area.y + idx, item, content_area.width)
          else
            buffer.write_string(content_area.x, content_area.y + idx, item.to_s, nil)
          end
        end

        # Clear remaining lines
        (items.size...content_area.height).each do |idx|
          content_area.width.times do |col|
            buffer.set(content_area.x + col, content_area.y + idx, " ", nil)
          end
        end
      end

      private

      def write_text_line(buffer, x, y, text_line, max_width)
        current_x = x
        text_line.spans.each do |span|
          break if current_x >= x + max_width

          content = span.content.to_s
          remaining = x + max_width - current_x
          content = content[0, remaining] if content.length > remaining

          style_hash = style_to_hash(span.style)
          content.each_char do |c|
            buffer.set(current_x, y, c, style_hash)
            current_x += 1
          end
        end

        # Fill rest with spaces
        while current_x < x + max_width
          buffer.set(current_x, y, " ", nil)
          current_x += 1
        end
      end

      def style_to_hash(style)
        return nil unless style

        hash = {}
        hash[:fg] = COLORS[style.fg] if style.fg
        hash[:bg] = BG_COLORS[style.bg] if style.bg
        hash[:bold] = true if style.bold
        hash[:dim] = true if style.dim
        hash[:underline] = true if style.underline
        hash[:link] = style.link if style.link
        hash.empty? ? nil : hash
      end
    end

    # Block with borders and title
    class Block
      BORDERS = {
        top_left: "\u250c", top_right: "\u2510",
        bottom_left: "\u2514", bottom_right: "\u2518",
        horizontal: "\u2500", vertical: "\u2502",
        left_t: "\u251c", right_t: "\u2524"
      }.freeze

      attr_reader :title, :borders, :border_style

      def initialize(title: nil, borders: [], border_style: nil)
        @title = title
        @borders = borders
        @border_style = border_style || Style.new
      end

      def render_to_buffer(buffer, area)
        style_hash = style_to_hash(border_style)

        has_top = borders.include?(:all) || borders.include?(:top)
        has_bottom = borders.include?(:all) || borders.include?(:bottom)
        has_left = borders.include?(:all) || borders.include?(:left)
        has_right = borders.include?(:all) || borders.include?(:right)

        if has_top
          render_top_border(buffer, area, has_left, has_right, style_hash)
        end

        if has_bottom
          render_bottom_border(buffer, area, has_left, has_right, style_hash)
        end

        # Side borders
        inner_start = has_top ? 1 : 0
        inner_end = has_bottom ? area.height - 2 : area.height - 1

        (inner_start..inner_end).each do |row|
          if has_left
            buffer.set(area.x, area.y + row, BORDERS[:vertical], style_hash)
          end
          if has_right
            buffer.set(area.x + area.width - 1, area.y + row, BORDERS[:vertical], style_hash)
          end
        end
      end

      def inner_area(area)
        has_top = borders.include?(:all) || borders.include?(:top)
        has_bottom = borders.include?(:all) || borders.include?(:bottom)
        has_left = borders.include?(:all) || borders.include?(:left)
        has_right = borders.include?(:all) || borders.include?(:right)

        x = area.x + (has_left ? 1 : 0)
        y = area.y + (has_top ? 1 : 0)
        w = area.width - (has_left ? 1 : 0) - (has_right ? 1 : 0)
        h = area.height - (has_top ? 1 : 0) - (has_bottom ? 1 : 0)

        Rect.new(x: x, y: y, width: [w, 0].max, height: [h, 0].max)
      end

      private

      def render_top_border(buffer, area, has_left, has_right, style_hash)
        x = area.x
        y = area.y

        if has_left
          buffer.set(x, y, BORDERS[:top_left], style_hash)
          x += 1
        end

        end_x = area.x + area.width - (has_right ? 1 : 0)
        middle_width = end_x - x

        if title && middle_width > 4
          title_str = " #{title} "
          padding = middle_width - title_str.length
          left_pad = [padding / 2, 0].max
          right_pad = [padding - left_pad, 0].max

          left_pad.times { buffer.set(x, y, BORDERS[:horizontal], style_hash); x += 1 }
          title_str.each_char { |c| buffer.set(x, y, c, style_hash); x += 1 }
          right_pad.times { buffer.set(x, y, BORDERS[:horizontal], style_hash); x += 1 }
        else
          middle_width.times { buffer.set(x, y, BORDERS[:horizontal], style_hash); x += 1 }
        end

        if has_right
          buffer.set(x, y, BORDERS[:top_right], style_hash)
        end
      end

      def render_bottom_border(buffer, area, has_left, has_right, style_hash)
        x = area.x
        y = area.y + area.height - 1

        if has_left
          buffer.set(x, y, BORDERS[:bottom_left], style_hash)
          x += 1
        end

        end_x = area.x + area.width - (has_right ? 1 : 0)
        (end_x - x).times { buffer.set(x, y, BORDERS[:horizontal], style_hash); x += 1 }

        if has_right
          buffer.set(x, y, BORDERS[:bottom_right], style_hash)
        end
      end

      def style_to_hash(style)
        return nil unless style

        hash = {}
        hash[:fg] = COLORS[style.fg] if style.fg
        hash[:bg] = BG_COLORS[style.bg] if style.bg
        hash[:bold] = true if style.bold
        hash[:dim] = true if style.dim
        hash[:underline] = true if style.underline
        hash[:link] = style.link if style.link
        hash.empty? ? nil : hash
      end
    end

    # Clear widget - fills area with spaces
    class Clear
      def render_to_buffer(buffer, area)
        area.height.times do |row|
          area.width.times do |col|
            buffer.set(area.x + col, area.y + row, " ", nil)
          end
        end
      end
    end
  end

  # Frame for rendering widgets with double-buffering
  class Frame
    attr_reader :area

    def initialize(area, buffer)
      @area = area
      @buffer = buffer
    end

    def render_widget(widget, target_area)
      widget.render_to_buffer(@buffer, target_area)
    end
  end

  # Screen buffer for flicker-free rendering
  class ScreenBuffer
    attr_reader :width, :height

    def initialize(width, height)
      @width = width
      @height = height
      @cells = Array.new(height) { Array.new(width) { {char: " ", style: nil} } }
    end

    def set(x, y, char, style = nil)
      return if x < 0 || x >= @width || y < 0 || y >= @height

      @cells[y][x] = {char: char, style: style}
    end

    def write_string(x, y, str, style = nil)
      return if y < 0 || y >= @height

      # Handle ANSI-styled strings by parsing them
      visible_x = x
      current_style = style
      in_escape = false
      escape_seq = ""

      str.each_char do |c|
        if c == "\e"
          in_escape = true
          escape_seq = +"\e"  # Mutable string
        elsif in_escape
          escape_seq << c
          if c =~ /[a-zA-Z]/
            in_escape = false
            # Parse escape sequence for style
            current_style = parse_escape_style(escape_seq, style)
            escape_seq = +""
          end
        else
          break if visible_x >= @width

          set(visible_x, y, c, current_style) if visible_x >= 0
          visible_x += 1
        end
      end

      # Fill rest of line if we started at x=0 (full line write)
      if x == 0
        (visible_x...@width).each { |fill_x| set(fill_x, y, " ", nil) }
      end
    end

    def render_to_terminal(prev_buffer = nil)
      output = []
      output << "\e[H" # Move to top-left

      @height.times do |y|
        line_changed = prev_buffer.nil? || row_changed?(y, prev_buffer)

        if line_changed
          output << "\e[#{y + 1};1H" # Position cursor
          output << render_row(y)
          output << "\e[K" # Clear to end of line
        end
      end

      print output.join
      $stdout.flush
    end

    private

    def row_changed?(y, prev_buffer)
      @cells[y] != prev_buffer.instance_variable_get(:@cells)[y]
    end

    def render_row(y)
      result = []
      current_style = nil
      current_link = nil

      @cells[y].each do |cell|
        cell_style = cell[:style]
        cell_link = cell_style&.dig(:link)

        # Handle link changes
        if cell_link != current_link
          result << "\e]8;;\e\\" if current_link # Close previous link
          result << "\e]8;;#{cell_link}\e\\" if cell_link # Open new link
          current_link = cell_link
        end

        # Handle style changes (excluding link)
        style_without_link = cell_style&.reject { |k, _| k == :link }
        style_without_link = nil if style_without_link&.empty?
        prev_style_without_link = current_style&.reject { |k, _| k == :link }
        prev_style_without_link = nil if prev_style_without_link&.empty?

        if style_without_link != prev_style_without_link
          result << "\e[0m" if prev_style_without_link
          result << style_to_ansi(style_without_link) if style_without_link
        end

        current_style = cell_style
        result << cell[:char]
      end

      result << "\e]8;;\e\\" if current_link # Close link at end
      result << "\e[0m" if current_style&.reject { |k, _| k == :link }&.any?
      result.join
    end

    def style_to_ansi(style)
      return "" unless style

      codes = []
      codes << style[:fg] if style[:fg]
      codes << style[:bg] if style[:bg]
      codes << 1 if style[:bold]
      codes << 2 if style[:dim]
      codes << 4 if style[:underline]

      codes.empty? ? "" : "\e[#{codes.join(";")}m"
    end

    def parse_escape_style(seq, base_style)
      return nil if seq == "\e[0m"

      codes = seq.match(/\e\[([0-9;]*)m/)&.[](1)&.split(";")&.map(&:to_i) || []
      return base_style if codes.empty?

      style = base_style&.dup || {}
      codes.each do |code|
        case code
        when 0 then style = {}
        when 1 then style[:bold] = true
        when 2 then style[:dim] = true
        when 30..37 then style[:fg] = code
        when 90..97 then style[:fg] = code
        when 40..47 then style[:bg] = code
        when 100..107 then style[:bg] = code
        end
      end
      style.empty? ? nil : style
    end
  end

  # Main TUI runtime
  class Runtime
    def initialize
      @original_state = nil
      @prev_buffer = nil
    end

    def draw
      current_area = area
      buffer = ScreenBuffer.new(current_area.width, current_area.height)

      frame = Frame.new(current_area, buffer)
      yield frame

      buffer.render_to_terminal(@prev_buffer)
      @prev_buffer = buffer
    end

    def area
      height, width = screen_size
      Rect.new(x: 0, y: 0, width: width, height: height)
    end

    def poll_event(timeout: 500)
      timeout_sec = timeout / 1000.0
      return nil unless IO.select([$stdin], nil, nil, timeout_sec)

      c = $stdin.getc
      return nil unless c

      case c
      when "\e"
        parse_escape_sequence
      when "\r", "\n"
        {type: :key, code: "enter"}
      when "\u007F", "\b"
        {type: :key, code: "backspace"}
      when "\u0003"
        {type: :key, code: "c", modifiers: ["ctrl"]}
      when "\u0004"
        {type: :key, code: "d", modifiers: ["ctrl"]}
      else
        {type: :key, code: c}
      end
    end

    # Layout helpers
    def layout_split(rect, direction:, constraints:)
      case direction
      when :vertical
        split_vertical(rect, constraints)
      when :horizontal
        split_horizontal(rect, constraints)
      else
        [rect]
      end
    end

    def constraint_length(value)
      Constraint::Length.new(value: value)
    end

    def constraint_fill(weight = 1)
      Constraint::Fill.new(weight: weight)
    end

    def constraint_percentage(value)
      Constraint::Percentage.new(value: value)
    end

    # Widget builders
    def paragraph(text:, style: nil)
      Widgets::Paragraph.new(text: text, style: style)
    end

    def list(items:, block: nil)
      Widgets::List.new(items: items, block: block)
    end

    def block(title: nil, borders: [], border_style: nil)
      Widgets::Block.new(title: title, borders: borders, border_style: border_style)
    end

    def clear
      Widgets::Clear.new
    end

    # Text helpers
    def text_span(content:, style: nil)
      TextSpan.new(content: content, style: style)
    end

    def text_line(spans:)
      TextLine.new(spans: spans)
    end

    def style(fg: nil, bg: nil, bold: false, dim: false, italic: false, underline: false, link: nil, modifiers: [])
      Style.new(
        fg: fg,
        bg: bg,
        bold: bold || modifiers.include?(:bold),
        dim: dim || modifiers.include?(:dim),
        italic: italic || modifiers.include?(:italic),
        underline: underline || modifiers.include?(:underline),
        link: link
      )
    end

    # Geometry helper
    def rect(x:, y:, width:, height:)
      Rect.new(x: x, y: y, width: width, height: height)
    end

    private

    def screen_size
      IO.console&.winsize || [24, 80]
    end

    def parse_escape_sequence
      return {type: :key, code: "escape"} unless IO.select([$stdin], nil, nil, 0.05)

      seq = $stdin.getc
      return {type: :key, code: "escape"} unless seq == "["
      return {type: :key, code: "escape"} unless IO.select([$stdin], nil, nil, 0.05)

      arrow = $stdin.getc
      case arrow
      when "A" then {type: :key, code: "up"}
      when "B" then {type: :key, code: "down"}
      when "C" then {type: :key, code: "right"}
      when "D" then {type: :key, code: "left"}
      else {type: :key, code: "escape"}
      end
    end

    def split_vertical(rect, constraints)
      total = rect.height
      areas = resolve_constraints(constraints, total)

      y = rect.y
      areas.map do |h|
        r = Rect.new(x: rect.x, y: y, width: rect.width, height: h)
        y += h
        r
      end
    end

    def split_horizontal(rect, constraints)
      total = rect.width
      areas = resolve_constraints(constraints, total)

      x = rect.x
      areas.map do |w|
        r = Rect.new(x: x, y: rect.y, width: w, height: rect.height)
        x += w
        r
      end
    end

    def resolve_constraints(constraints, total)
      # First pass: calculate fixed sizes
      fixed = 0
      fill_weight = 0

      constraints.each do |c|
        case c
        when Constraint::Length
          fixed += c.value
        when Constraint::Percentage
          fixed += (total * c.value / 100.0).to_i
        when Constraint::Fill
          fill_weight += c.weight
        end
      end

      remaining = [total - fixed, 0].max

      # Second pass: resolve all constraints
      constraints.map do |c|
        case c
        when Constraint::Length
          c.value
        when Constraint::Percentage
          (total * c.value / 100.0).to_i
        when Constraint::Fill
          fill_weight > 0 ? (remaining * c.weight / fill_weight.to_f).to_i : 0
        end
      end
    end
  end

  # Main entry point
  def self.run
    runtime = Runtime.new
    setup_terminal

    yield runtime
  ensure
    cleanup_terminal
  end

  def self.setup_terminal
    @original_state = `stty -g 2>/dev/null`.chomp rescue nil
    system("stty raw -echo 2>/dev/null")
    print "\e[?1049h" # Alternate screen
    print "\e[2J"     # Clear screen once at startup
    print "\e[?25l"   # Hide cursor
    $stdout.flush
  end

  def self.cleanup_terminal
    print "\e[?25h"   # Show cursor
    print "\e[?1049l" # Exit alternate screen
    system("stty #{@original_state} 2>/dev/null") if @original_state
  end
end
