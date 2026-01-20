# frozen_string_literal: true

require 'test_helper'

class OutputTest < Minitest::Test
  def setup
    @original_color = Deploio::Output.color_enabled
    Deploio::Output.color_enabled = false
  end

  def teardown
    Deploio::Output.color_enabled = @original_color
  end

  def test_success_message
    out, = capture_io { Deploio::Output.success('Operation complete') }
    assert_match(/✓ Operation complete/, out)
  end

  def test_error_message
    _, err = capture_io { Deploio::Output.error('Something went wrong') }

    assert_match(/✗ Something went wrong/, err)
  end

  def test_warning_message
    out, = capture_io { Deploio::Output.warning('Caution advised') }
    assert_match(/! Caution advised/, out)
  end

  def test_info_message
    out, = capture_io { Deploio::Output.info('Processing') }
    assert_match(/→ Processing/, out)
  end

  def test_command_message
    out, = capture_io { Deploio::Output.command('nctl get apps') }

    assert_match(/> nctl get apps/, out)
  end

  def test_table_output
    rows = [
      %w[app1 mini main],
      %w[app2 standard develop]
    ]

    out, = capture_io { Deploio::Output.table(rows, headers: %w[APP SIZE REVISION]) }

    assert_match(/APP/, out)
    assert_match(/SIZE/, out)
    assert_match(/REVISION/, out)
    assert_match(/app1/, out)
    assert_match(/app2/, out)
  end

  def test_table_with_empty_rows
    out, = capture_io { Deploio::Output.table([]) }

    assert_empty out
  end
end
