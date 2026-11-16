# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module Raix
  module Datacircle
    # What Datacircle's API answered when it gave no data (its HTTP status in #status), or why it could not be reached.
    class Error < StandardError
      attr_reader :status

      def initialize(message = nil, status: nil)
        super(message)
        @status = status
      end
    end

    # One HTTPS GET to Datacircle's open API, with no key: its answer as a Hash or an Array.
    class Client
      BASE = 'https://api.datacircle.dev/v1'

      def initialize(base_url: BASE)
        @base = base_url.to_s.chomp('/')
      end

      def get(path, params = {})
        uri = URI("#{@base}#{path}")
        query = params.reject { |_, value| value.nil? || value.to_s.strip.empty? }
        uri.query = URI.encode_www_form(query) unless query.empty?
        2.times do |attempt|
          response = request(uri)
          return parse(response) if response.is_a?(Net::HTTPSuccess)

          if response.code == '429' && attempt.zero?
            sleep(wait(response))
            next
          end
          raise Error.new(words(response), status: response.code.to_i)
        end
        raise Error.new("Datacircle's API answered 429 twice: wait a minute and call again", status: 429)
      end

      private

      def request(uri)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 15, read_timeout: 30) do |http|
          http.get(uri.request_uri, 'Accept' => 'application/json', 'User-Agent' => "raix-datacircle/#{VERSION}")
        end
      rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse => e
        raise Error, "Datacircle's API could not be reached: #{e.message}"
      end

      def parse(response)
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        raise Error.new("Datacircle's API answered #{response.code} with no JSON", status: response.code.to_i)
      end

      # The API asks to wait in Retry-After: its seconds, a minute at most.
      def wait(response)
        Integer(response['Retry-After'] || 30).clamp(1, 60)
      rescue ArgumentError
        30
      end

      # The API's own words: its error of a 4xx, else its status.
      def words(response)
        parsed = JSON.parse(response.body.to_s)
        parsed.is_a?(Hash) && parsed['error'] ? parsed['error'].to_s : "Datacircle's API answered #{response.code}"
      rescue JSON::ParserError
        "Datacircle's API answered #{response.code}"
      end
    end
  end
end
