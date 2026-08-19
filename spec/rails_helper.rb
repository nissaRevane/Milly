require "spec_helper"
# Force the test environment: the containers run with RAILS_ENV=development, and
# `||=` would leave it there -- which skips Bundler's :test group (shoulda-matchers
# et al. never get required) and points the suite at the development database.
ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

# Warden skips applying `sign_in` on requests it considers asset requests, and it
# defaults to treating anything under "/assets/" as one -- which would silently
# leave specs for AssetsController's member routes unauthenticated. Point it at
# the real asset pipeline prefix instead (see config/initializers/assets.rb).
require "warden/test/helpers"
Warden.test_mode! # idempotent; also mixes in the `asset_paths=` writer
Warden.asset_paths = %r{^/sprockets/}

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [Rails.root.join("spec/fixtures")]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include Devise::Test::IntegrationHelpers, type: :request
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
