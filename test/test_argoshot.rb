# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "argoshot"

class SignatureTest < Minitest::Test
  # The server's own test (jai-web-framework framework/Screenshots/tests/privacy/app.jai:194):
  # hmac_sha256("secret-of-the-customer-1234", "html=x&access_key=key-<tenant>"), lowercase hex.
  def test_server_vector
    client = Argoshot::Client.new("key-2", secret_key: "secret-of-the-customer-1234")
    assert_equal "https://api.argoshot.com/take?html=x&access_key=key-2&signature=9488e5f178e81282b921f410775de15b0767f894504cd18bd66f35616d60ffd1",
                 client.url(html: "x")
  end

  def test_signed_url
    client = Argoshot::Client.new("AK_test", secret_key: "SK_test")
    url = client.url(url: "https://example.com/a b?x=1&y=2", format: "png", full_page: true, viewport_width: 1280,
                     device_scale_factor: 1.5, hide_selectors: [".a", "#b .c"])
    assert_equal "https://api.argoshot.com/take?device_scale_factor=1.5&format=png&full_page=true&hide_selectors=.a&hide_selectors=%23b%20.c&url=https%3A%2F%2Fexample.com%2Fa%20b%3Fx%3D1%26y%3D2&viewport_width=1280&access_key=AK_test&signature=1a6f9d69eae82c57575f031ba76325705f5c0ddc6b48380a6fa7964c8a497b1c",
                 url
  end

  def test_non_ascii_html
    client = Argoshot::Client.new("AK_test", secret_key: "SK_test")
    assert_equal "https://api.argoshot.com/take?format=png&html=%3Ch1%3EHi%20%E2%80%94%20caf%C3%A9%20%2B%20%26%3C%2Fh1%3E&access_key=AK_test&signature=a1fb4eea53e2c394dce7ab32e31a26a2c8c85b8ebc53ac330ddb0cc441ee9eb7",
                 client.url(html: "<h1>Hi — café + &</h1>", format: "png")
  end

  def test_unsigned_custom_base_nil_skipped_string_keys
    client = Argoshot::Client.new("AK_test", base_url: "http://localhost:8080/")
    assert_equal "http://localhost:8080/take?format=png&url=https%3A%2F%2Fexample.com&access_key=AK_test",
                 client.url({ "url" => "https://example.com", "access_key" => "other" }, format: "png", selector: nil, signature: "x")
  end

  def test_reserved_characters
    assert_equal "styles=a%7Bcontent%3A%27%21%28%29%2A%27%7D", Argoshot.build_query("styles" => "a{content:'!()*'}")
  end
end

class ErrorTest < Minitest::Test
  def test_api_error
    body = JSON.generate("is_successful" => false, "error_code" => "selector_not_found",
                         "error_message" => "Nothing matches the selector: #hero",
                         "documentation_url" => "https://argoshot.com/docs/errors/selector-not-found/")
    e = Argoshot.parse_error(400, body)
    assert_equal "selector_not_found", e.code
    assert_equal "Nothing matches the selector: #hero", e.message
    assert_equal 400, e.status
    assert_equal "https://argoshot.com/docs/errors/selector-not-found/", e.documentation_url
  end

  def test_upgrade_retry_and_not_json
    e = Argoshot.parse_error(402, '{"is_successful":false,"error_code":"free_tier_exhausted","error_message":"Used.","upgrade_url":"https://argoshot.com/pricing"}', "5")
    assert_equal "free_tier_exhausted", e.code
    assert_equal "https://argoshot.com/pricing", e.upgrade_url
    assert_equal 5, e.retry_after
    bad = Argoshot.parse_error(502, "<html>Bad gateway</html>")
    assert_equal "http_error", bad.code
    assert_equal 502, bad.status
    assert_includes bad.message, "HTTP 502"
  end
end

class FakeResponse
  attr_reader :code, :body

  def initialize(code, body, headers = {})
    @code = code.to_s
    @body = body
    @headers = headers
  end

  def [](name)
    @headers[name]
  end
end

class TakeTest < Minitest::Test
  def fake(client, response)
    calls = []
    client.define_singleton_method(:perform) do |uri, request|
      calls << [uri, request]
      response
    end
    calls
  end

  def test_get_signed_with_header
    client = Argoshot::Client.new("AK_test", secret_key: "SK_test")
    calls = fake(client, FakeResponse.new(200, "\x89PNG".b))
    assert_equal "\x89PNG".b, client.take(url: "https://example.com", format: "png")
    uri, request = calls.first
    query = "format=png&url=https%3A%2F%2Fexample.com"
    assert_equal "https://api.argoshot.com/take?#{query}&signature=#{Argoshot.sign('SK_test', query)}", uri.to_s
    assert_equal "GET", request.method
    assert_equal "AK_test", request["X-Access-Key"]
  end

  def test_post_json_for_html
    client = Argoshot::Client.new("AK_test")
    calls = fake(client, FakeResponse.new(200, "ok"))
    client.take(html: "<h1>Hi</h1>", format: "png", async: false, hide_selectors: [".x"])
    uri, request = calls.first
    assert_equal "https://api.argoshot.com/take", uri.to_s
    assert_equal "POST", request.method
    assert_equal "application/json", request["Content-Type"]
    assert_equal({ "html" => "<h1>Hi</h1>", "format" => "png", "async" => false, "hide_selectors" => [".x"] }, JSON.parse(request.body))
  end

  def test_error_raises
    client = Argoshot::Client.new("bad")
    fake(client, FakeResponse.new(400, '{"is_successful":false,"error_code":"access_key_invalid","error_message":"No such access key."}'))
    e = assert_raises(Argoshot::Error) { client.take(url: "https://example.com") }
    assert_equal "access_key_invalid", e.code
    assert_equal 400, e.status
  end
end

class LiveTest < Minitest::Test
  def test_png
    skip "set ARGOSHOT_KEY to run the live test" unless ENV["ARGOSHOT_KEY"]
    client = Argoshot::Client.new(ENV["ARGOSHOT_KEY"], secret_key: ENV["ARGOSHOT_SECRET"])
    assert_equal "\x89PNG".b, client.take(url: "https://example.com", format: "png")[0, 4].b
  end
end
