# A line (actif or passif) that may be rattachée to one of its owner's biens.
#
# The link is optional, but it must never cross accounts: a property_id belonging to
# another user would satisfy the foreign key and then leak that account's bien (name
# and usage) onto this user's balance sheet — and, the other way round, deleting that
# bien would silently nullify a stranger's line. The controllers already scope the
# assignment; this validation is the model-side backstop.
module PropertyLinkable
  extend ActiveSupport::Concern

  included do
    belongs_to :property, optional: true

    validate :property_belongs_to_owner
  end

  private

  def property_belongs_to_owner
    errors.add(:property, :invalid) if property && property.user_id != user_id
  end
end
