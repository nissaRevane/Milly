module Users
  # La demande de réinitialisation envoie un email à une adresse qu'on choisit : sans
  # limite, c'est un moyen d'inonder la boîte de n'importe qui, et de brûler le quota du
  # relais SMTP au passage.
  class PasswordsController < Devise::PasswordsController
    include RateLimitable

    rate_limit to: 5, within: 15.minutes, only: :create,
               store: Milly::RATE_LIMIT_STORE, with: -> { too_many_attempts(new_user_password_path) }
  end
end
