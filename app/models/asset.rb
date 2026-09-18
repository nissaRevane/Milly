class Asset < ApplicationRecord
  include Historizable
  include Lifespanable
  include PropertyLinkable
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

  # Les types dont la plus-value sera imposée à la sortie. Un seul pour l'instant : le
  # placement financier — PEA, assurance-vie, compte-titres — dont la valeur affichée est
  # celle d'avant impôt. Un livret, un compte courant, une créance n'en portent aucun, et la
  # plus-value immobilière obéit à un abattement pour durée de détention qui n'est pas un taux.
  TAXABLE_TYPES = %w[financial_investment].freeze

  validates :name, presence: true
  validates :tax_rate, presence: true,
                       numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validate :asset_type_stays_out_of_real_estate

  # Un taux ne survit pas au type qui le portait : repasser un placement en livret le remet
  # à zéro, plutôt que de refuser l'enregistrement pour un champ que le formulaire ne montre
  # plus. Sans cela un taux oublié continuerait d'amputer l'actif en silence.
  before_validation :drop_tax_rate_unless_taxable

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

  # Ce type porte-t-il une fiscalité à la sortie ? Le taux, lui, reste facultatif : un PEA
  # imposable et un PEE défiscalisé sont deux placements financiers.
  def taxable_type?
    TAXABLE_TYPES.include?(asset_type)
  end

  # Ce placement-ci est-il réellement imposé ? Un PEE défiscalisé est un placement financier
  # sans taux : les écrans ne lui réclament pas de base imposable, rien n'en serait retranché.
  def taxed?
    taxable_type? && tax_rate.positive?
  end

  # Part de la plus-value qui partira en impôt, e.g. 18.6 -> 0.186. Pendant de #share_ratio
  # (voir Shareable), et arrondi comme lui par BalanceSheetAsset::LATENT_TAX_SQL.
  def tax_ratio
    tax_rate / 100
  end

  # La grande catégorie de l'actif — celle qui l'organise partout : sa liste, les groupes d'un
  # bilan, les bandes du miroir. Voir BreakdownCategory, qui la nomme et la colore.
  def category_key
    BreakdownCategory.for_asset(self)
  end

  # La liste rangée comme les écrans la lisent : par catégorie dans l'ordre du graphique, puis
  # par nom. Le bien est chargé avec, la catégorie de l'immobilier dépendant de son usage.
  def self.ordered_by_category
    BreakdownCategory.sort(includes(:property), BreakdownCategory::ASSETS)
  end

  # Seul l'actif immobilier se rattache à un bien : c'est le bien lui-même, vu du bilan.
  # Un compte courant dédié à un bien, un placement, une créance restent des actifs à part
  # — le bien ne les porte pas (voir PropertyLinkable).
  def property_linkable?
    real_estate?
  end

  # The bien's own actif, as opposed to a real_estate actif whose bien has been deleted
  # since (Property nullifies instead of destroying, to keep the balance sheet history).
  def owned_by_property?
    real_estate? && property_id.present?
  end

  # Le montant proposé quand l'actif entre dans un bilan, nil quand rien n'est connu.
  # Pour l'actif d'un bien c'est le prix d'achat : avant la première estimation, c'est la
  # seule valeur que l'utilisateur ait déjà saisie pour ce bien. Ce n'est qu'une
  # suggestion — le bilan reste ce que l'utilisateur y écrit.
  def suggested_value
    property.purchase_price if owned_by_property?
  end

  private

  # Voir Historizable : les lignes de bilan de cet actif, et le montant détenu qu'elles portent.
  def historized_lines
    balance_sheet_assets
  end

  def historized_amount(line)
    line.owned_value
  end

  def drop_tax_rate_unless_taxable
    self.tax_rate = 0 unless taxable_type?
  end

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
