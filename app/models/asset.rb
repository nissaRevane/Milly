class Asset < ApplicationRecord
  include PropertyLinkable
  include RiskCategorizable
  include Shareable

  belongs_to :user
  has_many :balance_sheet_assets, dependent: :destroy

  enum :asset_type, {
    cash: 0,
    checking_account: 1,
    savings_account: 2,
    financial_investment: 3,
    real_estate: 4,
    receivable: 5
  }, validate: true

  # "real_estate" is not a type the user picks: it belongs to a bien, which creates its
  # actif itself (Property#create_own_real_estate_asset). AssetsController keeps it out of
  # every write it accepts, and the validation below freezes it afterwards.
  RESERVED_ASSET_TYPE = "real_estate".freeze

  validates :name, presence: true
  validate :asset_type_stays_out_of_real_estate

  # The name of the bien's actif is the name of the bien: the two are the same thing on
  # the balance sheet, and AccountExport / db/seeds.rb resolve both by name.
  before_validation :adopt_property_name, if: -> { real_estate? && property }

  # Every type but the reserved one, for the form select.
  def self.selectable_asset_types
    asset_types.keys - [RESERVED_ASSET_TYPE]
  end

  def self.asset_type_label_for(type)
    EnumLabel.for("asset_types", type)
  end

  def asset_type_label
    self.class.asset_type_label_for(asset_type)
  end

  # The bien's own actif, as opposed to a real_estate actif whose bien has been deleted
  # since (Property nullifies instead of destroying, to keep the balance sheet history).
  def owned_by_property?
    real_estate? && property_id.present?
  end

  private

  def adopt_property_name
    self.name = property.name
  end

  # An existing actif never becomes immobilier, and the bien's actif never becomes
  # anything else: only creating a bien mints that type, and only deleting the bien
  # retires it. Creation itself stays open, for Property, db/seeds.rb and imports.
  def asset_type_stays_out_of_real_estate
    return if new_record? || !asset_type_changed?
    return unless [asset_type, asset_type_was].include?(RESERVED_ASSET_TYPE)

    errors.add(:asset_type, :reserved_for_property)
  end
end
