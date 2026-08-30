# La réponse commune aux limites de débit posées sur les écrans Devise.
#
# Une redirection avec un message plutôt qu'un 429 nu : ces trois écrans sont des
# formulaires que remplit un être humain, et celui qui vient de se tromper dix fois de
# mot de passe doit lire pourquoi on ne lui répond plus.
module RateLimitable
  extend ActiveSupport::Concern

  private

  def too_many_attempts(path)
    redirect_to path, alert: t("flash.errors.rate_limited"), status: :see_other
  end
end
