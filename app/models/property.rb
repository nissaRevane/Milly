class Property < ApplicationRecord
  belongs_to :user

  # :nullify, never :destroy — deleting a property must not erase the assets and
  # liabilities it grouped, otherwise the balance sheet history would lose lines.
  has_many :assets, dependent: :nullify
  has_many :liabilities, dependent: :nullify

  # The actif that *is* the bien, created with it and named after it. Unlinked, never
  # deleted, when the bien goes away — the has_many above already nullifies it.
  has_one :real_estate_asset,
          -> { where(asset_type: :real_estate) },
          class_name: "Asset",
          inverse_of: :property

  # Runs inside the save transaction: a bien that cannot get its actif is not created.
  after_create :create_own_real_estate_asset
  after_update :rename_real_estate_asset, if: :saved_change_to_name?

  enum :usage, {
    primary_residence: 0,
    rental: 1,
    secondary_residence: 2
  }, validate: true

  # Unique per user because the name is the identity of a bien outside the database:
  # AccountExport references it by name and db/seeds.rb resolves it by name, so two
  # "Maison" would collapse into one on an export → import round trip.
  validates :name, presence: true, uniqueness: { scope: :user_id }

  # Optional, like the two other descriptive fields: a bien is worth what the balance
  # sheet says today, the purchase price is only there to be compared with it.
  validates :purchase_price,
            numericality: { greater_than_or_equal_to: 0 },
            allow_nil: true

  def self.usage_label_for(usage)
    EnumLabel.for("property_usages", usage)
  end

  def usage_label
    self.class.usage_label_for(usage)
  end

  private

  # db/seeds.rb and AccountExport imports may already carry the actif of the bien; it is
  # matched by name, so the one created here is the very record they then update.
  # Named apart from the create_real_estate_asset the has_one generates, which it would
  # otherwise shadow.
  # Le risque « Moyen » n'est qu'un point de départ, modifiable sur la fiche de l'actif :
  # il vaut mieux que le défaut de colonne (« Faible »), qui décrirait mal de l'immobilier.
  # db/seeds.rb et les imports AccountExport écrasent ce niveau avec celui qu'ils portent.
  def create_own_real_estate_asset
    assets.create!(user: user, name: name, asset_type: :real_estate, risk_level: :medium)
  end

  def rename_real_estate_asset
    real_estate_asset&.update!(name: name)
  end
end
