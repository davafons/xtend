require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Xtend
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1
    config.time_zone = "Tokyo"
    config.x.demo = ENV["XTEND_DEMO"] == "1"
    # AI apps may register for OAuth only with callbacks on these hosts (or their subdomains), or on loopback.
    # Anyone can register, so this keeps an app on a stranger's site from asking you to approve it.
    # Add a host with XTEND_OAUTH_REDIRECT_HOSTS="example.com other.example".
    config.x.oauth_redirect_hosts = %w[claude.ai claude.com chatgpt.com openai.com cursor.com x.ai grok.com] +
      ENV.fetch("XTEND_OAUTH_REDIRECT_HOSTS", "").split

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
