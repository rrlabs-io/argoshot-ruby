# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"

require_relative "argoshot/version"

# A small client for the Argoshot screenshot API (https://argoshot.com/docs). Standard library only.
#
#   client = Argoshot::Client.new("ACCESS_KEY", secret_key: "SECRET_KEY")
#   File.binwrite("example.png", client.take(url: "https://example.com", format: "png"))
#   og_image = client.url(url: "https://example.com", viewport_width: 1200, viewport_height: 630)
module Argoshot
  DEFAULT_BASE_URL = "https://api.argoshot.com"
  CLIENT_OWN = %w[access_key signature].freeze

  # An error the API answered (its error_code and error_message), or a response that was not the API's
  # (code "http_error").
  class Error < StandardError
    attr_reader :code, :status, :documentation_url, :upgrade_url, :returned_status_code, :matched_string,
                :retry_after, :body

    def initialize(code:, message:, status: 0, documentation_url: nil, upgrade_url: nil,
                   returned_status_code: nil, matched_string: nil, retry_after: nil, body: nil)
      super(message)
      @code = code
      @status = status
      @documentation_url = documentation_url
      @upgrade_url = upgrade_url
      @returned_status_code = returned_status_code
      @matched_string = matched_string
      @retry_after = retry_after
      @body = body
    end
  end

  class Client
    attr_reader :access_key, :secret_key, :base_url, :timeout

    def initialize(access_key, secret_key: nil, base_url: DEFAULT_BASE_URL, timeout: 120)
      raise ArgumentError, "Argoshot: an access key is required" if access_key.nil? || access_key.to_s.empty?

      @access_key = access_key.to_s
      @secret_key = secret_key.nil? || secret_key.to_s.empty? ? nil : secret_key.to_s
      @base_url = (base_url || DEFAULT_BASE_URL).to_s.sub(%r{/+\z}, "")
      @timeout = timeout
    end

    # A GET /take URL for these options (for <img src> or og:image), signed when a secret key is set.
    # The access key is in the URL: for public pages, use a key set to "signed requests only".
    def url(options = nil, **kwargs)
      query = Argoshot.build_query(merge(options, kwargs))
      query += "&" unless query.empty?
      query += "access_key=#{Argoshot.encode(access_key)}"
      query += "&signature=#{Argoshot.sign(secret_key, query)}" if secret_key
      "#{base_url}/take?#{query}"
    end

    # Render and return the file's bytes (a binary String). Raises Argoshot::Error on failure.
    # GET for url captures (signed when a secret key is set); a JSON POST when html or markdown is given.
    def take(options = nil, **kwargs)
      opts = Argoshot.clean(merge(options, kwargs))
      if opts.key?("html") || opts.key?("markdown")
        uri = URI("#{base_url}/take")
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(opts)
      else
        query = Argoshot.build_query(opts)
        query += "&signature=#{Argoshot.sign(secret_key, query)}" if secret_key
        uri = URI("#{base_url}/take?#{query}")
        request = Net::HTTP::Get.new(uri)
      end
      send_request(uri, request)
    end

    # GET /usage: renders total, available and used, and the plan's limits. Costs nothing.
    def usage
      uri = URI("#{base_url}/usage")
      JSON.parse(send_request(uri, Net::HTTP::Get.new(uri)))
    end

    private

    def merge(options, kwargs)
      merged = {}
      (options || {}).each { |k, v| merged[k.to_s] = v }
      kwargs.each { |k, v| merged[k.to_s] = v }
      merged
    end

    def send_request(uri, request)
      request["X-Access-Key"] = access_key
      request["User-Agent"] = "argoshot-ruby/#{VERSION}"
      request["Accept-Encoding"] = "identity"
      response = perform(uri, request)
      status = response.code.to_i
      body = response.body.to_s
      raise Argoshot.parse_error(status, body, response["Retry-After"]) unless status >= 200 && status < 300

      body
    end

    def perform(uri, request)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                          open_timeout: timeout, read_timeout: timeout) do |http|
        http.request(request)
      end
    end
  end

  module_function

  # The query string of these options: names sorted, lists repeated, nil left out (no access key).
  def build_query(options)
    opts = clean(options)
    parts = []
    opts.keys.sort.each do |name|
      Array(opts[name]).each do |v|
        next if v.nil?

        parts << "#{encode(name)}=#{encode(text(v))}"
      end
    end
    parts.join("&")
  end

  # The signature the API checks: lowercase hex HMAC-SHA256 of the query string, under the secret key.
  def sign(secret_key, query)
    OpenSSL::HMAC.hexdigest("SHA256", secret_key.to_s, query.to_s)
  end

  # An Argoshot::Error from an error response's status, body and Retry-After header.
  def parse_error(status, body, retry_after = nil)
    retry_seconds = retry_after.to_s.strip =~ /\A\d+\z/ ? retry_after.to_i : nil
    data = begin
      JSON.parse(body.to_s)
    rescue JSON::ParserError
      nil
    end
    if data.is_a?(Hash) && data["error_code"].is_a?(String)
      return Error.new(code: data["error_code"], message: data["error_message"] || data["error_code"], status: status,
                       documentation_url: data["documentation_url"], upgrade_url: data["upgrade_url"],
                       returned_status_code: data["returned_status_code"], matched_string: data["matched_string"],
                       retry_after: retry_seconds, body: body)
    end
    snippet = body.to_s[0, 200]
    Error.new(code: "http_error", message: "HTTP #{status}#{snippet.empty? ? '' : ": #{snippet}"}", status: status,
              retry_after: retry_seconds, body: body)
  end

  def clean(options)
    out = {}
    (options || {}).each do |k, v|
      name = k.to_s
      next if v.nil? || CLIENT_OWN.include?(name)

      out[name] = v
    end
    out
  end

  def text(value)
    case value
    when true then "true"
    when false then "false"
    else value.to_s
    end
  end

  # RFC 3986: everything but A-Z a-z 0-9 - . _ ~ is percent-encoded (a space is %20, a + is %2B).
  def encode(value)
    value.to_s.dup.force_encoding(Encoding::BINARY).gsub(/[^A-Za-z0-9\-._~]/n) { |c| format("%%%02X", c.ord) }
  end
end
