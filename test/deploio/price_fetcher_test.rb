# frozen_string_literal: true

require "test_helper"

class PriceFetcherTest < Minitest::Test
  def setup
    @price_fetcher = Deploio::PriceFetcher.new
    @sample_prices = {
      "postgres" => {
        "nine-db-xs" => 65,
        "nine-db-s" => 97,
        "nine-db-m" => 117,
        "nine-db-l" => 149,
        "nine-db-xl" => 201,
        "nine-db-xxl" => 253,
        "nine-single-db-s" => 5,
        "nine-single-db-m" => 9,
        "nine-single-db-l" => 20
      },
      "mysql" => {
        "nine-db-xs" => 65,
        "nine-db-s" => 97
      },
      "keyvaluestore" => {"base" => 15},
      "opensearch" => {"base" => 60},
      "app" => {"micro" => 8, "mini" => 16, "standard-1" => 32, "standard-2" => 58},
      "ram_per_gib" => 5
    }
  end

  def test_format_price_with_value
    assert_equal "CHF 65/mo", @price_fetcher.format_price(65)
    assert_equal "CHF 16/mo", @price_fetcher.format_price(16)
  end

  def test_format_price_with_nil
    assert_equal "-", @price_fetcher.format_price(nil)
  end

  def test_price_for_postgres_service
    @price_fetcher.instance_variable_set(:@prices, @sample_prices)

    spec = {"forProvider" => {"machineType" => "nine-db-xs"}}
    assert_equal 65, @price_fetcher.price_for_service("postgres", spec)

    spec = {"forProvider" => {"machineType" => "nine-db-m"}}
    assert_equal 117, @price_fetcher.price_for_service("postgres", spec)

    spec = {"forProvider" => {"singleDBMachineType" => "nine-single-db-l"}}
    assert_equal 20, @price_fetcher.price_for_service("postgres", spec)
  end

  def test_price_for_mysql_service
    @price_fetcher.instance_variable_set(:@prices, @sample_prices)

    spec = {"forProvider" => {"machineType" => "nine-db-xs"}}
    assert_equal 65, @price_fetcher.price_for_service("mysql", spec)
  end

  def test_price_for_keyvaluestore_256mi
    @price_fetcher.instance_variable_set(:@prices, @sample_prices)

    spec = {"forProvider" => {"memorySize" => "256Mi"}}
    # base 15 + (256/1024) * 5 = 15 + 1.25 = 16.25, rounded to 16
    assert_equal 16, @price_fetcher.price_for_service("keyvaluestore", spec)
  end

  def test_price_for_keyvaluestore_1gi
    @price_fetcher.instance_variable_set(:@prices, @sample_prices)

    spec = {"forProvider" => {"memorySize" => "1Gi"}}
    # base 15 + 1 * 5 = 20
    assert_equal 20, @price_fetcher.price_for_service("keyvaluestore", spec)
  end

  def test_price_for_keyvaluestore_512mi
    @price_fetcher.instance_variable_set(:@prices, @sample_prices)

    spec = {"forProvider" => {"memorySize" => "512Mi"}}
    # base 15 + (512/1024) * 5 = 15 + 2.5 = 17.5, rounded to 18
    assert_equal 18, @price_fetcher.price_for_service("keyvaluestore", spec)
  end

  def test_price_for_opensearch
    @price_fetcher.instance_variable_set(:@prices, @sample_prices)

    spec = {}
    assert_equal 60, @price_fetcher.price_for_service("opensearch", spec)
  end

  def test_price_for_unknown_service_type
    @price_fetcher.instance_variable_set(:@prices, @sample_prices)

    spec = {}
    assert_nil @price_fetcher.price_for_service("unknown", spec)
  end

  def test_price_for_postgres_without_machine_type
    @price_fetcher.instance_variable_set(:@prices, @sample_prices)

    spec = {"forProvider" => {}}
    assert_nil @price_fetcher.price_for_service("postgres", spec)
  end

  def test_price_for_service_returns_nil_for_unknown_machine_type
    @price_fetcher.instance_variable_set(:@prices, @sample_prices)

    spec = {"forProvider" => {"machineType" => "unknown-type"}}
    assert_nil @price_fetcher.price_for_service("postgres", spec)
  end

  def test_price_for_app_micro
    @price_fetcher.instance_variable_set(:@prices, @sample_prices)

    app = {"spec" => {"forProvider" => {"config" => {"size" => "micro"}}}}
    assert_equal 8, @price_fetcher.price_for_app(app)
  end

  def test_price_for_app_mini
    @price_fetcher.instance_variable_set(:@prices, @sample_prices)

    app = {"spec" => {"forProvider" => {"config" => {"size" => "mini"}}}}
    assert_equal 16, @price_fetcher.price_for_app(app)
  end

  def test_price_for_app_standard_1
    @price_fetcher.instance_variable_set(:@prices, @sample_prices)

    app = {"spec" => {"forProvider" => {"config" => {"size" => "standard-1"}}}}
    assert_equal 32, @price_fetcher.price_for_app(app)
  end

  def test_price_for_app_with_spec_replicas
    @price_fetcher.instance_variable_set(:@prices, @sample_prices)

    app = {"spec" => {"forProvider" => {"config" => {"size" => "mini"}, "replicas" => 3}}}
    assert_equal 48, @price_fetcher.price_for_app(app) # 16 * 3
  end

  def test_price_for_app_with_status_replicas
    @price_fetcher.instance_variable_set(:@prices, @sample_prices)

    # Status replicas takes precedence over spec replicas
    app = {
      "spec" => {"forProvider" => {"config" => {"size" => "mini"}, "replicas" => 3}},
      "status" => {"atProvider" => {"replicas" => 2}}
    }
    assert_equal 32, @price_fetcher.price_for_app(app) # 16 * 2 (uses status)
  end

  def test_price_for_app_with_zero_replicas
    @price_fetcher.instance_variable_set(:@prices, @sample_prices)

    app = {
      "spec" => {"forProvider" => {"config" => {"size" => "mini"}}},
      "status" => {"atProvider" => {"replicas" => 0}}
    }
    assert_equal 0, @price_fetcher.price_for_app(app)
  end

  def test_price_for_app_defaults_to_micro
    @price_fetcher.instance_variable_set(:@prices, @sample_prices)

    app = {"spec" => {"forProvider" => {"config" => {}}}}
    assert_equal 8, @price_fetcher.price_for_app(app)
  end

  def test_price_for_app_with_empty_data
    @price_fetcher.instance_variable_set(:@prices, @sample_prices)

    app = {}
    assert_equal 8, @price_fetcher.price_for_app(app) # defaults to micro * 1
  end
end
