require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.secret_key_base = ENV.fetch("SECRET_KEY_BASE") { SecureRandom.hex(64) }
end
