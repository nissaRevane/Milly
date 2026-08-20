# Les grandes catégories qui rangent le patrimoine : trois familles à l'actif, trois au passif.
# Ce ne sont pas les types d'enum — un compte courant, un livret et une créance répondent tous
# à la même question, de quoi dispose-t-on tout de suite — mais le vocabulaire par lequel Milly
# organise TOUS ses écrans : la liste des actifs, celle des passifs, les groupes d'un bilan et
# les bandes du miroir du tableau de bord parlent de ces catégories-là, dans cet ordre et avec
# ces couleurs (voir .chart-series-* dans application.css). Le type précis d'une ligne reste sa
# donnée, modifiable sur sa fiche ; c'est la catégorie qui l'organise partout ailleurs.
#
# L'ordre des deux listes est celui de l'empilement du graphique en partant de l'axe, et il est
# figé : une catégorie tient sa teinte de sa clé, et une même couleur doit nommer le même poste
# d'un écran à l'autre.
#
# +split+ marque la seule famille qui garde son détail : l'immobilier, éclaté par usage du bien,
# parce qu'une résidence principale, une secondaire et un locatif ne se pilotent pas de la même
# façon. Le détail s'y lit à la nuance, jamais à la teinte.
#
# Seule cette famille-là est éclatée. Un compte courant rattaché à un bien reste une liquidité :
# regrouper toutes les lignes d'un bien est le travail de l'onglet Immobilier (voir
# BalanceSheet#property_positions), pas celui d'une catégorie.
module BreakdownCategory
  ASSETS = [
    { key: "liquidity", types: %w[cash checking_account savings_account receivable] },
    { key: "real_estate", types: %w[real_estate], split: true },
    { key: "financial_investment", types: %w[financial_investment] }
  ].freeze

  # Le passif s'ordonne en partant de l'axe : d'abord ce qui n'est adossé à aucun bien — les
  # dettes diverses, qui rassemblent la dette court terme et les autres crédits, ces deux
  # dettes du quotidien qu'aucun bien ne porte — puis les dépôts de garantie, puis les
  # crédits immobiliers et leur détail par usage.
  LIABILITIES = [
    { key: "short_term_debt", types: %w[short_term_debt other_credit] },
    { key: "security_deposit", types: %w[security_deposit] },
    { key: "real_estate_loan", types: %w[real_estate_loan], split: true }
  ].freeze

  # L'ordre des usages à l'intérieur de l'immobilier. Il ne suit pas celui de l'enum mais celui
  # du dégradé qui les colore, de la résidence principale au locatif : la nuance ne peut dire
  # de quel usage il s'agit que si le rang, lui, ne bouge jamais.
  #
  # La liste ordonne, elle ne filtre pas (voir .rows) : un usage ajouté à l'enum sans passer par
  # ici se range en queue, sans teinte attitrée, plutôt que de disparaître en silence d'un écran
  # qui prétend montrer tout le patrimoine.
  USAGE_ORDER = %w[primary_residence secondary_residence rental].freeze

  # La sous-catégorie des lignes immobilières qu'aucun bien ne porte encore.
  UNASSIGNED_USAGE = "unassigned".freeze

  # La catégorie d'un actif, d'un passif : la famille de son type, suivie de l'usage du bien
  # qu'il porte quand cette famille est éclatée.
  def self.for_asset(asset)
    key_for(ASSETS, asset.asset_type, asset.property&.usage)
  end

  def self.for_liability(liability)
    key_for(LIABILITIES, liability.liability_type, liability.property&.usage)
  end

  # Chaque type d'enum tombe dans une famille et une seule. Le .fetch n'a pas de repli : un type
  # ajouté à un enum sans être rangé ici doit casser la suite de tests, pas disparaître en
  # silence d'un écran qui prétend tout montrer.
  def self.key_for(categories, type, usage)
    category = index(categories).fetch(type)
    return category[:key] unless category[:split]

    "#{category[:key]}:#{usage || UNASSIGNED_USAGE}"
  end

  # Les clés de toutes les catégories, dans l'ordre où elles s'empilent et se lisent : celui des
  # familles, l'éclatée laissant place à ses usages puis au bucket non rattaché.
  def self.keys(categories)
    rows(categories).map(&:first)
  end

  # Les [clé, famille, usage, usage abrégé] de chaque catégorie, dans ce même ordre — figé, et
  # surtout pas déduit des montants : une catégorie qui changerait de rang, donc de couleur, d'un
  # bilan à l'autre rendrait la courbe illisible.
  #
  # Le bucket non rattaché n'a pas de forme courte à lui : son libellé sert des deux côtés.
  def self.rows(categories)
    categories.flat_map do |category|
      family = label(category[:key])
      next [[category[:key], family, nil, nil]] unless category[:split]

      usages = (USAGE_ORDER | Property.usages.keys).map { |usage|
        [usage, Property.usage_label_for(usage), Property.usage_short_label_for(usage)]
      }
      unassigned = I18n.t("views.shared.unassigned_property")
      usages << [UNASSIGNED_USAGE, unassigned, unassigned]
      usages.map { |usage, usage_label, usage_short| ["#{category[:key]}:#{usage}", family, usage_label, usage_short] }
    end
  end

  # Les clés des familles seules, sans leur détail : ce qu'un filtre de liste propose. Filtrer
  # « Immobilier » retient tous les usages — la nuance dit un usage, elle n'est pas un critère.
  def self.family_keys(categories)
    categories.map { |category| category[:key] }
  end

  # Les types d'enum que retient une famille, pour la clause SQL d'un filtre.
  def self.types_for(categories, family_key)
    index_by_key(categories).fetch(family_key)[:types]
  end

  # Le nom de la famille d'une clé, éclatée ou non : « Immobilier » pour « real_estate:rental ».
  def self.label(key)
    I18n.t("views.shared.breakdown_categories.#{family_of(key)}")
  end

  # L'usage que porte une clé éclatée, nil sinon.
  def self.sublabel(key)
    usage = key.split(":")[1]
    return nil if usage.nil?
    return I18n.t("views.shared.unassigned_property") if usage == UNASSIGNED_USAGE

    Property.usage_label_for(usage)
  end

  # Le libellé d'un seul tenant, là où il n'y a qu'une ligne à donner : une pastille, l'en-tête
  # d'un groupe, l'infobulle d'une bande.
  def self.full_label(key)
    usage = sublabel(key)
    return label(key) if usage.nil?

    I18n.t("views.shared.breakdown_split", type: label(key), usage: usage)
  end

  # Des lignes rangées comme les écrans les lisent : par catégorie dans l'ordre du graphique,
  # puis par nom. Le tri se fait en Ruby et non en SQL — la catégorie n'est pas une colonne, elle
  # se déduit du type de la ligne et de l'usage du bien qu'elle porte.
  def self.sort(records, categories)
    rank = keys(categories).each_with_index.to_h
    records.sort_by { |record| [rank.fetch(record.category_key, rank.size), record.name] }
  end

  # {clé de catégorie => lignes}, les catégories dans l'ordre du graphique et les vides absentes :
  # la vue itère sur ce qu'elle reçoit sans avoir à connaître l'ordre. Une clé hors de l'ordre
  # connu passe en queue plutôt que de faire disparaître ses lignes.
  def self.group(records, categories)
    grouped = records.group_by(&:category_key)
    known = keys(categories) & grouped.keys

    (known + (grouped.keys - known)).to_h { |key| [key, grouped[key]] }
  end

  def self.family_of(key)
    key.split(":").first
  end
  private_class_method :family_of

  def self.index(categories)
    categories.flat_map { |category| category[:types].map { |type| [type, category] } }.to_h
  end
  private_class_method :index

  def self.index_by_key(categories)
    categories.to_h { |category| [category[:key], category] }
  end
  private_class_method :index_by_key
end
