# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "fileutils"

module Deploio
  class PriceFetcher
    CACHE_DIR = File.expand_path("~/.deploio")
    CACHE_FILE = File.join(CACHE_DIR, "prices.json")
    CACHE_TTL = 24 * 60 * 60 # 24 hours in seconds
    API_URL = "https://calculator-api-production.2deb129.deploio.app/product"

    def initialize
      @prices = nil
    end

    def fetch
      @prices ||= load_cached_prices || fetch_and_cache_prices
    end

    def price_for_service(type, spec)
      fetch
      return nil unless @prices

      case type
      when "postgres", "mysql"
        price_for_database(type, spec)
      when "keyvaluestore"
        price_for_keyvaluestore(spec)
      when "opensearch"
        price_for_opensearch
      end
    end

    def format_price(price)
      return "-" if price.nil?

      "CHF #{price}/mo"
    end

    private

    def load_cached_prices
      return nil unless File.exist?(CACHE_FILE)

      cache_data = JSON.parse(File.read(CACHE_FILE))
      cached_at = cache_data["cached_at"]
      return nil if cached_at.nil? || Time.now.to_i - cached_at > CACHE_TTL

      cache_data["prices"]
    rescue JSON::ParserError, Errno::ENOENT
      nil
    end

    def fetch_and_cache_prices
      prices = fetch_prices_from_api
      return nil if prices.nil?

      cache_prices(prices)
      prices
    rescue StandardError
      nil
    end

    def fetch_prices_from_api
      uri = URI.parse(API_URL)
      response = Net::HTTP.get_response(uri)
      return nil unless response.is_a?(Net::HTTPSuccess)

      products = JSON.parse(response.body)
      build_price_map(products)
    rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError
      nil
    end

    def build_price_map(products)
      prices = {
        "postgres" => {},
        "mysql" => {},
        "keyvaluestore" => { "base" => 15 },
        "opensearch" => { "base" => 60 },
        "ram_per_gib" => 5
      }

      products.each do |product|
        name = product["name"]
        list_price = product["list_price"]

        case name
        when /^PostgreSQL - (nine-(?:db|single-db)-\S+)/
          machine_type = normalize_machine_type($1)
          prices["postgres"][machine_type] = list_price
        when /^MySQL - (nine-(?:db|single-db)-\S+)/
          machine_type = normalize_machine_type($1)
          prices["mysql"][machine_type] = list_price
        when "Managed Service: Key-Value Store (Redis compatible)"
          prices["keyvaluestore"]["base"] = list_price
        when "Managed Service: OpenSearch (Elasticsearch compatible)"
          prices["opensearch"]["base"] = list_price
        end
      end

      prices
    end

    def normalize_machine_type(raw)
      # "nine-single-db-l - 10GB" -> "nine-single-db-l"
      raw.split(" ").first
    end

    def cache_prices(prices)
      FileUtils.mkdir_p(CACHE_DIR)
      cache_data = {
        "cached_at" => Time.now.to_i,
        "prices" => prices
      }
      File.write(CACHE_FILE, JSON.pretty_generate(cache_data))
    end

    def price_for_database(type, spec)
      for_provider = spec.dig("forProvider") || {}
      machine_type = for_provider["machineType"] || for_provider["singleDBMachineType"]
      return nil if machine_type.nil?

      @prices.dig(type, machine_type)
    end

    def price_for_keyvaluestore(spec)
      base_price = @prices.dig("keyvaluestore", "base") || 15
      ram_price = @prices["ram_per_gib"] || 5

      memory_size = spec.dig("forProvider", "memorySize")
      return base_price if memory_size.nil?

      # Parse memory size (e.g., "256Mi", "1Gi", "512Mi")
      gib = parse_memory_to_gib(memory_size)
      (base_price + (gib * ram_price)).round
    end

    def price_for_opensearch
      @prices.dig("opensearch", "base") || 60
    end

    def parse_memory_to_gib(memory_str)
      case memory_str
      when /^(\d+(?:\.\d+)?)Gi$/
        $1.to_f
      when /^(\d+(?:\.\d+)?)Mi$/
        $1.to_f / 1024
      when /^(\d+(?:\.\d+)?)Ki$/
        $1.to_f / (1024 * 1024)
      else
        0
      end
    end
  end
end
