module Users
  # Une IP ne peut pas essayer des mots de passe indéfiniment. Devise ne dit pas si c'est
  # l'email ou le mot de passe qui est faux, mais sans limite de débit rien n'empêche d'en
  # essayer des milliers — et un gestionnaire de patrimoine est une cible qui vaut la peine.
  class SessionsController < Devise::SessionsController
    include RateLimitable

    rate_limit to: 10, within: 5.minutes, only: :create,
               store: Milly::RATE_LIMIT_STORE, with: -> { too_many_attempts(new_user_session_path) }
  end
end
