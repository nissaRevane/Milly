module Users
  # Devise handles the password change itself; only the landing spot changes, so the
  # confirmation flash shows up on the account page the form was submitted from
  # rather than on the bilans index.
  class RegistrationsController < Devise::RegistrationsController
    include RateLimitable

    # L'inscription est ouverte à tous, donc automatisable : sans limite, une seule IP peut
    # remplir la base de comptes jetables.
    rate_limit to: 5, within: 1.hour, only: :create,
               store: Milly::RATE_LIMIT_STORE, with: -> { too_many_attempts(new_user_registration_path) }

    protected

    def after_update_path_for(_resource)
      account_path
    end
  end
end
