# frozen_string_literal: true

require "test_helper"

class SharedOptionsTest < Minitest::Test
  # Test class that includes SharedOptions to test the resolve_project method
  class TestCommand < Thor
    include Deploio::SharedOptions

    no_commands do
      def initialize_for_test(nctl_client)
        @nctl = nctl_client
      end

      # Expose resolve_project for testing
      def test_resolve_project(project)
        resolve_project(project)
      end
    end
  end

  def setup
    @nctl = Minitest::Mock.new
    @cmd = TestCommand.new
    @cmd.initialize_for_test(@nctl)
  end

  def test_resolve_project_prepends_org_to_simple_name
    @nctl.expect(:current_org, "renuo")

    result = @cmd.test_resolve_project("myproject")

    assert_equal "renuo-myproject", result
    @nctl.verify
  end

  def test_resolve_project_prepends_org_to_name_with_hyphen
    @nctl.expect(:current_org, "renuo")

    result = @cmd.test_resolve_project("my-project")

    assert_equal "renuo-my-project", result
    @nctl.verify
  end

  def test_resolve_project_prepends_org_to_name_starting_with_org
    # This is the key bug fix: project names like "renuo-website-v3"
    # should still get the org prefix to become "renuo-renuo-website-v3"
    @nctl.expect(:current_org, "renuo")

    result = @cmd.test_resolve_project("renuo-website-v3")

    assert_equal "renuo-renuo-website-v3", result
    @nctl.verify
  end

  def test_resolve_project_does_not_modify_when_project_equals_org
    # Special case: when the project name is the same as the org name
    @nctl.expect(:current_org, "renuo")

    result = @cmd.test_resolve_project("renuo")

    assert_equal "renuo", result
    @nctl.verify
  end

  def test_resolve_project_returns_as_is_when_no_org
    @nctl.expect(:current_org, nil)

    result = @cmd.test_resolve_project("myproject")

    assert_equal "myproject", result
    @nctl.verify
  end
end
