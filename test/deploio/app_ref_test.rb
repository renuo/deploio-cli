# frozen_string_literal: true

require 'test_helper'

class AppRefTest < Minitest::Test
  def test_parses_from_available_apps
    available = {
      'deploio-sqlite-deploio-sqlite' => { project_name: 'deploio-sqlite', app_name: 'deploio-sqlite' },
      'deploio-landing-page-develop' => { project_name: 'deploio-landing-page', app_name: 'develop' }
    }

    ref = Deploio::AppRef.new('deploio-sqlite-deploio-sqlite', available_apps: available)

    assert_equal 'deploio-sqlite', ref.project_name
    assert_equal 'deploio-sqlite', ref.app_name
  end

  def test_parses_hyphenated_project_name_from_available_apps
    available = {
      'deploio-landing-page-develop' => { project_name: 'deploio-landing-page', app_name: 'develop' }
    }

    ref = Deploio::AppRef.new('deploio-landing-page-develop', available_apps: available)

    assert_equal 'deploio-landing-page', ref.project_name
    assert_equal 'develop', ref.app_name
  end

  def test_full_name_returns_project_name_app_name
    available = {
      'deploio-landing-page-develop' => { project_name: 'deploio-landing-page', app_name: 'develop' }
    }

    ref = Deploio::AppRef.new('deploio-landing-page-develop', available_apps: available)

    assert_equal 'deploio-landing-page-develop', ref.full_name
  end

  def test_raises_error_when_app_not_found
    available = {
      'myproject-staging' => { project_name: 'myproject', app_name: 'staging' }
    }

    error = assert_raises(Deploio::AppNotFoundError) do
      Deploio::AppRef.new('nonexistent-app', available_apps: available)
    end

    assert_match(/App not found/, error.message)
  end

  def test_includes_suggestions_when_app_not_found
    available = {
      'myproject-staging' => { project_name: 'myproject', app_name: 'staging' },
      'myproject-production' => { project_name: 'myproject', app_name: 'production' }
    }

    error = assert_raises(Deploio::AppNotFoundError) do
      Deploio::AppRef.new('myproject-stagin', available_apps: available)
    end

    assert_match(/Did you mean/, error.message)
    assert_match(/myproject-staging/, error.message)
  end

  def test_raises_error_when_no_available_apps
    error = assert_raises(Deploio::AppNotFoundError) do
      Deploio::AppRef.new('myproject-staging')
    end

    assert_match(/App not found/, error.message)
  end

  def test_equality
    available = {
      'project-app' => { project_name: 'project', app_name: 'app' }
    }

    ref1 = Deploio::AppRef.new('project-app', available_apps: available)
    ref2 = Deploio::AppRef.new('project-app', available_apps: available)

    assert_equal ref1, ref2
  end
end
