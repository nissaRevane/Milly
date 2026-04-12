require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = true
  config.cache_store = :null_store
  config.active_support.deprecation = :log
  config.active_support.disallowed_deprecations = :raise
  config.active_record.migration_error = :page_load
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
end
