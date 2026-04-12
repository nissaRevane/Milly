require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

module Milly
  class Application < Rails::Application
    config.load_defaults 8.0
    config.autoload_lib(ignore: %w[assets tasks])
    config.i18n.default_locale = :fr
    config.i18n.available_locales = [:fr, :en]
    config.time_zone = "Paris"
    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot, dir: "spec/factories"
    end
  end
end
