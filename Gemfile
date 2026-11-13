source "https://rubygems.org"

gem "rails", "~> 8.1.4"
gem "propshaft"
gem "sqlite3", ">= 2.1"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails", "~> 4.4"
gem "lostcoords-ui", "~> 0.10.0", git: "https://github.com/lostcoords/ui.git", tag: "v0.10.0"

group :test do
  gem "minitest-mock", require: false
end

gem "rubyzip", "~> 3.7", require: "zip"


gem "solid_queue", "~> 1.7"

gem "kamal", "~> 2.12", group: :development, require: false

group :development do
  gem "tensaku", git: "https://github.com/lostcoords/tensaku.git", ref: "55168f5e153c84c25048ed666ad2e058da53da67"
end
