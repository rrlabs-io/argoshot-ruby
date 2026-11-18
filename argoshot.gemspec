# frozen_string_literal: true

require_relative "lib/argoshot/version"

Gem::Specification.new do |spec|
  spec.name = "argoshot"
  spec.version = Argoshot::VERSION
  spec.authors = ["Argoshot"]
  spec.summary = "Official client for the Argoshot screenshot API."
  spec.description = "Screenshots, PDFs and signed og:image URLs of any web page or HTML, from the Argoshot API. Standard library only."
  spec.homepage = "https://argoshot.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6"
  spec.metadata = {
    "homepage_uri" => "https://argoshot.com",
    "documentation_uri" => "https://argoshot.com/docs",
    "source_code_uri" => "https://github.com/rrlabs-io/argoshot-ruby",
    "rubygems_mfa_required" => "true"
  }
  spec.files = Dir["lib/**/*.rb"] + %w[README.md LICENSE]
  spec.require_paths = ["lib"]
end
