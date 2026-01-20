# frozen_string_literal: true

require 'test_helper'

class AppResolverTest < Minitest::Test
  def setup
    @nctl = MockNctlClient.new(dry_run: true)
  end

  def test_raises_error_when_app_not_found_in_dry_run
    # In dry_run mode, get_all_apps returns empty, so app won't be found
    resolver = Deploio::AppResolver.new(nctl_client: @nctl)

    error = assert_raises(Deploio::AppNotFoundError) do
      resolver.resolve(app_name: 'myproject-staging')
    end

    assert_match(/App not found/, error.message)
  end

  def test_raises_error_when_no_app_specified_and_no_git_remote
    resolver = Deploio::AppResolver.new(nctl_client: @nctl)
    resolver.instance_variable_set(:@git_remote_url, nil)

    error = assert_raises(Deploio::Error) { resolver.resolve }

    assert_match(/No app specified/, error.message)
  end

  def test_resolves_from_available_apps
    nctl = MockNctlClient.new(apps: [
      { 'metadata' => { 'namespace' => 'n10518', 'name' => 'develop' } }
    ])
    resolver = Deploio::AppResolver.new(nctl_client: nctl)

    result = resolver.resolve(app_name: 'n10518-develop')

    assert_equal 'n10518', result.project_name
    assert_equal 'develop', result.app_name
  end

  def test_resolves_short_name_with_current_org
    nctl = MockNctlClient.new(
      apps: [{ 'metadata' => { 'namespace' => 'myorg-myproject', 'name' => 'staging' } }],
      current_org: 'myorg'
    )
    resolver = Deploio::AppResolver.new(nctl_client: nctl)

    # Can resolve using short name (without org prefix)
    result = resolver.resolve(app_name: 'myproject-staging')

    assert_equal 'myorg-myproject', result.project_name
    assert_equal 'staging', result.app_name
  end

  def test_short_name_for_strips_org_prefix
    nctl = MockNctlClient.new(current_org: 'myorg')
    resolver = Deploio::AppResolver.new(nctl_client: nctl)

    assert_equal 'myproject-staging', resolver.short_name_for('myorg-myproject', 'staging')
  end

  def test_short_name_for_keeps_full_name_without_org
    nctl = MockNctlClient.new(current_org: nil)
    resolver = Deploio::AppResolver.new(nctl_client: nctl)

    assert_equal 'someorg-myproject-staging', resolver.short_name_for('someorg-myproject', 'staging')
  end

  class MockNctlClient
    def initialize(apps: [], current_org: nil, dry_run: false)
      @apps = apps
      @current_org = current_org
    end

    def get_all_apps
      @apps
    end

    def current_org
      @current_org
    end
  end
end
