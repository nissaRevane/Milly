class BalanceSheetAsset < ApplicationRecord
  belongs_to :balance_sheet
  belongs_to :asset

  # Le montant détenu avant impôt : la valeur saisie, ramenée à la quote-part. L'arrondi de
  # la quote-part avant la multiplication n'est pas décoratif : voir BalanceSheet#total_assets.
  #
  # Ce n'est PAS le montant que les écrans additionnent — voir OWNED_VALUE_SQL, qui en
  # retranche la fiscalité latente. Le brut ne se lit qu'à côté du net, là où l'on veut savoir
  # ce que l'impôt coûte (le détail d'une ligne de bilan).
  GROSS_OWNED_VALUE_SQL =
    "ROUND(balance_sheet_assets.value * ROUND(assets.ownership_share / 100, 4), 2)".freeze

  # La base imposable détenue : les versements cumulés, ramenés à la quote-part exactement
  # comme la valeur l'est au-dessus. Les deux s'arrondissent au même moment, si bien que leur
  # différence — la plus-value — retombe au centime sur ce que les écrans affichent.
  OWNED_INVESTED_VALUE_SQL =
    "ROUND(COALESCE(balance_sheet_assets.invested_value, balance_sheet_assets.value)" \
    " * ROUND(assets.ownership_share / 100, 4), 2)".freeze

  # L'impôt qui serait dû si la ligne était liquidée à cette date : la plus-value détenue,
  # au taux de sortie de l'actif (voir Asset::TAXABLE_TYPES).
  #
  # La plus-value est la différence de deux montants DÉJÀ arrondis, et non le produit arrondi
  # d'une différence : c'est ce qui fait que « investi + plus-value = brut détenu » et
  # « plus-value × taux = impôt » tiennent tous deux à l'écran, sur une quote-part comme sur
  # une détention pleine.
  #
  # Base inconnue (invested_value nul) : COALESCE la ramène à la valeur, donc pas de
  # plus-value et pas d'impôt. Mieux vaut ne rien retrancher qu'imposer une plus-value égale
  # à la valeur entière du placement. GREATEST écarte les moins-values : elles ne donnent
  # aucun crédit d'impôt ici.
  LATENT_TAX_SQL = <<~SQL.squish.freeze
    ROUND(GREATEST(#{GROSS_OWNED_VALUE_SQL} - #{OWNED_INVESTED_VALUE_SQL}, 0)
      * ROUND(assets.tax_rate / 100, 4), 2)
  SQL

  # Ce que la ligne vaut vraiment : le brut détenu, moins ce que le fisc prendrait à la
  # sortie. C'est LE montant de Milly — le seul que les totaux, la courbe du tableau de bord,
  # les ventilations et l'historique d'une ligne additionnent, et la raison pour laquelle le
  # patrimoine net affiché est déjà net de fiscalité. En constante parce que plusieurs
  # lectures s'en servent et qu'un arrondi qui divergerait entre elles ferait dire deux
  # montants différents au même bilan selon la page qui le lit.
  #
  # Sans taux de sortie — c'est le cas de tout ce qui n'est pas un placement imposé — l'impôt
  # vaut zéro et ce montant est le brut, à l'identique.
  OWNED_VALUE_SQL = "(#{GROSS_OWNED_VALUE_SQL} - #{LATENT_TAX_SQL})".freeze

  validates :value, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :asset_id, uniqueness: { scope: :balance_sheet_id }
  validates :invested_value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Un actif n'entre pas dans un bilan clos hors de sa période de détention. Le formulaire
  # ne le propose déjà plus (BalanceSheetAssetsController#set_available_assets) ; ceci en
  # est le filet côté modèle. À la création seulement : une ligne enregistrée est de
  # l'histoire, et une période resserrée après coup sur l'actif ne doit pas la rendre
  # immodifiable.
  validate :asset_within_its_lifespan, on: :create

  # Une ligne ne traverse jamais deux comptes. asset_id arrive d'un formulaire, et un id
  # forgé désignant l'actif d'un autre utilisateur satisfait la clé étrangère : le bilan
  # afficherait alors le nom, la catégorie et le bien de cet inconnu. Le contrôleur ne
  # propose déjà que les actifs de l'utilisateur (#set_available_assets), mais il ne fait
  # que remplir un select — ceci en est le filet côté modèle, exactement comme
  # PropertyLinkable#property_belongs_to_owner pour le rattachement à un bien.
  #
  # Sur toutes les validations et pas seulement à la création : réaffecter une ligne
  # existante passe par le même paramètre.
  validate :asset_belongs_to_the_same_account

  # Une base imposable ne survit pas à l'actif qui la portait. Le formulaire d'une ligne
  # masque — donc désactive — son champ quand l'actif choisi n'est pas imposé : sans ce
  # filet, réaffecter une ligne d'un PEA vers un livret laisserait la base de l'un collée à
  # l'autre, prête à ressortir en impôt le jour où ce livret redeviendrait un placement.
  before_validation :drop_invested_value_unless_taxed

  # Le pendant Ruby des trois constantes ci-dessus : voir chacune pour la lecture du calcul.
  def gross_owned_value
    (value * asset.share_ratio).round(2)
  end

  # La base imposable ramenée à la quote-part, nil tant qu'elle n'est pas saisie : c'est à
  # elle que se compare le brut détenu, jamais au montant total que porte le champ.
  def owned_invested_value
    return nil if invested_value.nil?

    (invested_value * asset.share_ratio).round(2)
  end

  def capital_gain
    return 0.to_d if invested_value.nil?

    [gross_owned_value - owned_invested_value, 0].max
  end

  def latent_tax
    (capital_gain * asset.tax_ratio).round(2)
  end

  def owned_value
    gross_owned_value - latent_tax
  end

  # La catégorie d'une ligne est celle de l'actif qu'elle chiffre : c'est par elle que le bilan
  # groupe ses lignes (voir BalanceSheet#assets_by_category).
  delegate :category_key, to: :asset

  private

  def drop_invested_value_unless_taxed
    self.invested_value = nil unless asset&.taxable_type?
  end

  def asset_belongs_to_the_same_account
    return if asset.nil? || balance_sheet.nil?
    return if asset.user_id == balance_sheet.user_id

    errors.add(:asset, :invalid)
  end

  def asset_within_its_lifespan
    return if asset.nil? || balance_sheet.nil?
    return if asset.available_on?(balance_sheet.closing_date)

    errors.add(:asset, :outside_lifespan)
  end
end
