# argoshot

The official Ruby client for [Argoshot](https://argoshot.com), the screenshot API: screenshots, PDFs and signed
`og:image` URLs of any web page or HTML. **Free to start.** Docs: https://argoshot.com/docs

Standard library only (`net/http`, `openssl`, `json`). Ruby 2.6+.

## Install

```sh
gem install argoshot
```

or in your Gemfile: `gem "argoshot"`. Get your access key (and secret key, for signed URLs) from the dashboard's API
keys page.

## Screenshot to a file

```ruby
require "argoshot"

client = Argoshot::Client.new(ENV.fetch("ARGOSHOT_ACCESS_KEY"))

png = client.take(url: "https://example.com", format: "png", full_page: true, block_cookie_banners: true)
File.binwrite("example.png", png)
```

## Signed og:image URL

`url` builds a `GET /take` link for `<img src>` or `<meta property="og:image">`. With a secret key it is signed
(HMAC-SHA256 of the query string), so nobody can change its options. Set the key to **signed requests only** in the
dashboard before you put its links in public pages.

```ruby
client = Argoshot::Client.new(ENV.fetch("ARGOSHOT_ACCESS_KEY"), secret_key: ENV.fetch("ARGOSHOT_SECRET_KEY"))

og_image = client.url(
  url: "https://example.com/blog/my-post",
  viewport_width: 1200,
  viewport_height: 630,
  format: "png",
  cache: true,
  cache_ttl: 86_400
)
# <meta property="og:image" content="<%= og_image %>">
```

## HTML to PNG

When `html` (or `markdown`) is given, `take` sends a JSON `POST` instead of a long query string.

```ruby
card = client.take(
  html: '<div style="font: 64px system-ui; padding: 80px">Hello from Argoshot</div>',
  format: "png",
  viewport_width: 1200,
  viewport_height: 630
)
File.binwrite("card.png", card)
```

## Options

Options are the API's own names (https://argoshot.com/docs/options), as keyword arguments or a hash: `url`, `html`,
`format`, `viewport_width`, `viewport_height`, `viewport_device`, `full_page`, `block_cookie_banners`, `block_ads`,
`dark_mode`, `selector`, `cache`, `cache_ttl` and 140 more. Lists are arrays: `hide_selectors: [".banner", "#chat"]`.

## Errors

A failed request raises `Argoshot::Error` with the API's `code` (e.g. `selector_not_found`,
`screenshots_limit_reached`), `message`, HTTP `status`, `documentation_url`, and `upgrade_url` / `retry_after` when the
API gives them. All codes: https://argoshot.com/docs/errors

```ruby
begin
  client.take(url: "https://example.com", selector: "#missing", error_on_selector_not_found: true)
rescue Argoshot::Error => e
  warn "#{e.code}: #{e.message}"
end
```

## Usage

```ruby
client.usage # => {"total"=>..., "available"=>..., "used"=>..., ...}
```

## Configuration

```ruby
Argoshot::Client.new(access_key, secret_key: nil, base_url: "https://api.argoshot.com", timeout: 120)
```

Note: a key set to *signed requests only* cannot send JSON `POST` requests (the API refuses them), so `take(html: ...)`
needs a key that permits unsigned requests.

## Licence

MIT
