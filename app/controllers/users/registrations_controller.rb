module Users
  # Devise handles the password change itself; only the landing spot changes, so the
  # confirmation flash shows up on the account page the form was submitted from
  # rather than on the bilans index.
  class RegistrationsController < Devise::RegistrationsController
    protected

    def after_update_path_for(_resource)
      account_path
    end
  end
end
