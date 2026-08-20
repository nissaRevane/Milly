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

  # Les deux bornes de la vie d'un bien et les deux bornes qu'elles donnent, par défaut,
  # à chacun de ses actifs et passifs (voir Lifespanable).
  LIFESPAN_MIRROR = { "acquired_on" => :started_on, "sold_on" => :ended_on }.freeze

  # Runs inside the save transaction: a bien that cannot get its actif is not created.
  after_create :create_own_real_estate_asset
  after_update :rename_real_estate_asset, if: :saved_change_to_name?
  after_update :propagate_lifespan_to_lines,
               if: -> { LIFESPAN_MIRROR.keys.any? { |field| saved_change_to_attribute?(field) } }

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

  # Les deux dates sont facultatives — un bien encore détenu n'a pas de date de vente, et
  # une date d'acquisition oubliée ne rend pas le bien inutilisable — mais on ne vend pas
  # avant d'avoir acheté.
  validate :sold_on_after_acquired_on

  def self.usage_label_for(usage)
    EnumLabel.for("property_usages", usage)
  end

  def usage_label
    self.class.usage_label_for(usage)
  end

  # La forme abrégée du même usage — « RP », « RS » — pour les endroits qui n'ont pas la
  # largeur d'un libellé entier : une pastille sur écran étroit, une légende de graphique.
  def self.usage_short_label_for(usage)
    EnumLabel.for("property_usages_short", usage)
  end

  def usage_short_label
    self.class.usage_short_label_for(usage)
  end

  private

  # db/seeds.rb and AccountExport imports may already carry the actif of the bien; it is
  # matched by name, so the one created here is the very record they then update.
  # Named apart from the create_real_estate_asset the has_one generates, which it would
  # otherwise shadow.
  def create_own_real_estate_asset
    assets.create!(user: user, name: name, asset_type: :real_estate)
  end

  def rename_real_estate_asset
    real_estate_asset&.update!(name: name)
  end

  def sold_on_after_acquired_on
    return if acquired_on.nil? || sold_on.nil? || sold_on >= acquired_on

    errors.add(:sold_on, :sold_before_acquired)
  end

  # Les actifs et passifs rattachés suivent le bien quand il corrige sa date d'achat ou
  # déclare sa vente : la période du bien est leur période par défaut, et un défaut qui ne
  # bougerait qu'à la création laisserait la ligne sur une date que le bien a démentie.
  #
  # Seules les bornes restées à la valeur du bien sont reprises : celle que l'utilisateur a
  # saisie lui-même — un compte courant ouvert bien après l'achat — est la sienne, et le
  # bien n'a pas à l'écraser.
  def propagate_lifespan_to_lines
    (assets + liabilities).each do |line|
      updates = LIFESPAN_MIRROR.filter_map do |property_field, line_field|
        next unless saved_change_to_attribute?(property_field)

        was, now = saved_change_to_attribute(property_field)
        next unless line[line_field] == was

        [line_field, now]
      end

      line.update!(updates.to_h) if updates.any?
    end
  end
end
