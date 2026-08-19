# A line (actif or passif) that may be rattachée to one of its owner's biens.
#
# The link is optional, and two things bound it.
#
# It must never cross accounts: a property_id belonging to another user would satisfy the
# foreign key and then leak that account's bien (name and usage) onto this user's balance
# sheet — and, the other way round, deleting that bien would silently nullify a stranger's
# line. The controllers already scope the assignment; this validation is the model-side
# backstop.
#
# And it must mean something: seules les lignes qu'un bien porte réellement se rattachent à
# lui — son propre actif, ses crédits immobiliers, les dépôts de garantie de ses locataires.
# Rattacher un compte courant ou une dette court terme à un bien n'énonce rien, et gonflait
# le « Brut » du bien dans l'onglet Immobilier. Chaque modèle répond de ses propres types
# avec #property_linkable?.
module PropertyLinkable
  extend ActiveSupport::Concern

  included do
    belongs_to :property, optional: true

    validate :property_belongs_to_owner
    validate :property_link_means_something
  end

  private

  def property_belongs_to_owner
    errors.add(:property, :invalid) if property && property.user_id != user_id
  end

  def property_link_means_something
    errors.add(:property, :not_linkable) if property_id && !property_linkable?
  end
end
