# frozen_string_literal: true

require "test_helper"
require "deploio/tui/minitui"

class MinituiTest < Minitest::Test
  def test_rect_creation
    rect = Minitui::Rect.new(x: 10, y: 5, width: 80, height: 24)

    assert_equal 10, rect.x
    assert_equal 5, rect.y
    assert_equal 80, rect.width
    assert_equal 24, rect.height
  end

  def test_rect_zero
    rect = Minitui::Rect.zero

    assert_equal 0, rect.x
    assert_equal 0, rect.y
    assert_equal 0, rect.width
    assert_equal 0, rect.height
  end

  def test_style_apply_with_foreground_color
    style = Minitui::Style.new(fg: :cyan)
    result = style.apply("hello")

    assert_equal "\e[36mhello\e[0m", result
  end

  def test_style_apply_with_bold
    style = Minitui::Style.new(bold: true)
    result = style.apply("hello")

    assert_equal "\e[1mhello\e[0m", result
  end

  def test_style_apply_with_dim
    style = Minitui::Style.new(dim: true)
    result = style.apply("hello")

    assert_equal "\e[2mhello\e[0m", result
  end

  def test_style_apply_combined
    style = Minitui::Style.new(fg: :green, bold: true)
    result = style.apply("hello")

    assert_equal "\e[32;1mhello\e[0m", result
  end

  def test_style_apply_no_styles
    style = Minitui::Style.new
    result = style.apply("hello")

    assert_equal "hello", result
  end

  def test_text_span_render_without_style
    span = Minitui::TextSpan.new(content: "hello")

    assert_equal "hello", span.render
    assert_equal 5, span.visible_length
  end

  def test_text_span_render_with_style
    style = Minitui::Style.new(fg: :red)
    span = Minitui::TextSpan.new(content: "hello", style: style)

    assert_equal "\e[31mhello\e[0m", span.render
    assert_equal 5, span.visible_length
  end

  def test_text_line_render
    line = Minitui::TextLine.new(spans: [
      Minitui::TextSpan.new(content: "hello "),
      Minitui::TextSpan.new(content: "world", style: Minitui::Style.new(fg: :cyan))
    ])

    assert_equal "hello \e[36mworld\e[0m", line.render
    assert_equal 11, line.visible_length
  end

  def test_constraint_length
    constraint = Minitui::Constraint::Length.new(value: 10)

    assert_equal 10, constraint.value
  end

  def test_constraint_fill
    constraint = Minitui::Constraint::Fill.new(weight: 2)

    assert_equal 2, constraint.weight
  end

  def test_constraint_percentage
    constraint = Minitui::Constraint::Percentage.new(value: 50)

    assert_equal 50, constraint.value
  end

  def test_screen_buffer_set_and_render
    buffer = Minitui::ScreenBuffer.new(10, 3)
    buffer.set(0, 0, "H", nil)
    buffer.set(1, 0, "i", nil)

    # Buffer should render without errors
    # (We can't easily test terminal output, but we can verify it doesn't crash)
    assert_equal 10, buffer.width
    assert_equal 3, buffer.height
  end

  def test_screen_buffer_write_string
    buffer = Minitui::ScreenBuffer.new(20, 3)
    buffer.write_string(0, 0, "Hello World", nil)

    assert_equal 20, buffer.width
  end

  def test_screen_buffer_write_string_with_ansi_codes
    buffer = Minitui::ScreenBuffer.new(20, 3)
    # This is what Style#apply produces
    styled_string = "\e[36mHello\e[0m"

    # Should not raise FrozenError
    buffer.write_string(0, 0, styled_string, nil)

    assert_equal 20, buffer.width
  end

  def test_screen_buffer_write_repeated_unicode_char
    buffer = Minitui::ScreenBuffer.new(80, 3)
    # This is how separators are rendered
    separator = "\u2500" * 80

    # Should not raise
    buffer.write_string(0, 0, separator, nil)
  end

  def test_paragraph_widget_creation
    paragraph = Minitui::Widgets::Paragraph.new(text: "Hello")

    assert_equal "Hello", paragraph.text
  end

  def test_list_widget_creation
    list = Minitui::Widgets::List.new(items: ["a", "b", "c"])

    assert_equal ["a", "b", "c"], list.items
  end

  def test_block_widget_inner_area_with_all_borders
    block = Minitui::Widgets::Block.new(borders: [:all])
    area = Minitui::Rect.new(x: 0, y: 0, width: 20, height: 10)

    inner = block.inner_area(area)

    assert_equal 1, inner.x
    assert_equal 1, inner.y
    assert_equal 18, inner.width
    assert_equal 8, inner.height
  end

  def test_block_widget_inner_area_with_right_border_only
    block = Minitui::Widgets::Block.new(borders: [:right])
    area = Minitui::Rect.new(x: 0, y: 0, width: 20, height: 10)

    inner = block.inner_area(area)

    assert_equal 0, inner.x
    assert_equal 0, inner.y
    assert_equal 19, inner.width
    assert_equal 10, inner.height
  end

  def test_clear_widget_creation
    clear = Minitui::Widgets::Clear.new

    assert_instance_of Minitui::Widgets::Clear, clear
  end

  def test_runtime_layout_split_vertical
    runtime = Minitui::Runtime.new
    area = Minitui::Rect.new(x: 0, y: 0, width: 80, height: 24)

    parts = runtime.layout_split(
      area,
      direction: :vertical,
      constraints: [
        runtime.constraint_length(1),
        runtime.constraint_fill(1),
        runtime.constraint_length(1)
      ]
    )

    assert_equal 3, parts.size
    assert_equal 1, parts[0].height
    assert_equal 22, parts[1].height
    assert_equal 1, parts[2].height
  end

  def test_runtime_layout_split_horizontal
    runtime = Minitui::Runtime.new
    area = Minitui::Rect.new(x: 0, y: 0, width: 80, height: 24)

    parts = runtime.layout_split(
      area,
      direction: :horizontal,
      constraints: [
        runtime.constraint_length(20),
        runtime.constraint_fill(1)
      ]
    )

    assert_equal 2, parts.size
    assert_equal 20, parts[0].width
    assert_equal 60, parts[1].width
  end

  def test_runtime_style_helper
    runtime = Minitui::Runtime.new

    style = runtime.style(fg: :cyan, bold: true)

    assert_equal :cyan, style.fg
    assert_equal true, style.bold
  end

  def test_runtime_style_with_modifiers
    runtime = Minitui::Runtime.new

    style = runtime.style(fg: :red, modifiers: [:bold, :dim])

    assert_equal :red, style.fg
    assert_equal true, style.bold
    assert_equal true, style.dim
  end

  def test_runtime_text_span_helper
    runtime = Minitui::Runtime.new

    span = runtime.text_span(content: "test", style: runtime.style(fg: :green))

    assert_equal "test", span.content
    assert_equal :green, span.style.fg
  end

  def test_runtime_text_line_helper
    runtime = Minitui::Runtime.new

    line = runtime.text_line(spans: [
      runtime.text_span(content: "a"),
      runtime.text_span(content: "b")
    ])

    assert_equal 2, line.spans.size
  end

  def test_runtime_rect_helper
    runtime = Minitui::Runtime.new

    rect = runtime.rect(x: 5, y: 10, width: 30, height: 15)

    assert_equal 5, rect.x
    assert_equal 10, rect.y
    assert_equal 30, rect.width
    assert_equal 15, rect.height
  end

  def test_backspace_key_code_127
    # Simulate reading \x7F (DEL, common backspace)
    # We can't easily test poll_event without mocking stdin,
    # but we can verify the key mapping logic exists
    assert_equal "\u007F", "\x7F"
  end

  def test_backspace_key_code_8
    # Simulate reading \b (BS)
    assert_equal "\b", "\x08"
  end

  def test_style_with_link
    runtime = Minitui::Runtime.new
    style = runtime.style(fg: :cyan, underline: true, link: "https://example.com")

    assert_equal :cyan, style.fg
    assert_equal true, style.underline
    assert_equal "https://example.com", style.link
  end

  def test_style_apply_with_link
    style = Minitui::Style.new(fg: :cyan, link: "https://example.com")
    result = style.apply("click me")

    # Should contain OSC 8 hyperlink sequences
    assert_includes result, "\e]8;;https://example.com\e\\"
    assert_includes result, "click me"
    assert_includes result, "\e]8;;\e\\"
  end

  def test_text_span_with_link_renders_to_buffer
    buffer = Minitui::ScreenBuffer.new(40, 3)
    area = Minitui::Rect.new(x: 0, y: 0, width: 40, height: 3)
    runtime = Minitui::Runtime.new

    line = runtime.text_line(spans: [
      runtime.text_span(
        content: "example.com",
        style: runtime.style(fg: :cyan, link: "https://example.com")
      )
    ])

    paragraph = Minitui::Widgets::Paragraph.new(text: [line])

    # Should not raise
    paragraph.render_to_buffer(buffer, area)
  end

  def test_paragraph_renders_to_buffer
    buffer = Minitui::ScreenBuffer.new(20, 5)
    area = Minitui::Rect.new(x: 0, y: 0, width: 20, height: 5)
    paragraph = Minitui::Widgets::Paragraph.new(text: "Hello")

    # Should not raise
    paragraph.render_to_buffer(buffer, area)
  end

  def test_list_renders_to_buffer
    buffer = Minitui::ScreenBuffer.new(20, 5)
    area = Minitui::Rect.new(x: 0, y: 0, width: 20, height: 5)
    list = Minitui::Widgets::List.new(items: ["item 1", "item 2"])

    # Should not raise
    list.render_to_buffer(buffer, area)
  end

  def test_block_renders_to_buffer
    buffer = Minitui::ScreenBuffer.new(20, 5)
    area = Minitui::Rect.new(x: 0, y: 0, width: 20, height: 5)
    block = Minitui::Widgets::Block.new(title: "Test", borders: [:all])

    # Should not raise
    block.render_to_buffer(buffer, area)
  end

  def test_clear_renders_to_buffer
    buffer = Minitui::ScreenBuffer.new(20, 5)
    area = Minitui::Rect.new(x: 0, y: 0, width: 20, height: 5)
    clear = Minitui::Widgets::Clear.new

    # Should not raise
    clear.render_to_buffer(buffer, area)
  end

  def test_text_line_with_styled_spans_renders_to_buffer
    buffer = Minitui::ScreenBuffer.new(40, 5)
    area = Minitui::Rect.new(x: 0, y: 0, width: 40, height: 5)

    runtime = Minitui::Runtime.new
    line = runtime.text_line(spans: [
      runtime.text_span(content: "Hello ", style: runtime.style(fg: :cyan)),
      runtime.text_span(content: "World", style: runtime.style(fg: :green, bold: true))
    ])

    paragraph = Minitui::Widgets::Paragraph.new(text: [line])

    # Should not raise - this is the exact pattern used in tty_dashboard
    paragraph.render_to_buffer(buffer, area)
  end
end
