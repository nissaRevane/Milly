Devise.setup do |config|
  config.mailer_sender = "noreply@milly.app"
  require "devise/orm/active_record"
  config.case_insensitive_keys = [:email]
  config.strip_whitespace_keys = [:email]
  config.skip_session_storage = [:http_auth]
  config.stretches = Rails.env.test? ? 1 : 12
  config.reconfirmable = false
  config.expire_all_remember_me_on_sign_out = true
  # Dix caractères et non six : le compte protège un patrimoine complet, et l'inscription
  # est ouverte à tous. Devise applique la longueur à l'inscription comme au changement.
  config.password_length = 10..128
  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/
  config.reset_password_within = 6.hours

  # « Si ce compte existe, un email vient de partir » plutôt que « email introuvable » :
  # sans cela, le formulaire de mot de passe oublié dit à qui le demande quelles adresses
  # ont un compte ici — c'est-à-dire qui gère son patrimoine sur Milly.
  config.paranoid = true
  config.sign_out_via = :delete
  config.responder.error_status = :unprocessable_entity
  config.responder.redirect_status = :see_other
  config.navigational_formats = ["*/*", :html, :turbo_stream]
end
