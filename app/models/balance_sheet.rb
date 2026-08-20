class BalanceSheet < ApplicationRecord
  # One property (or the "non rattaché" bucket, where +property+ is nil) seen through
  # this balance sheet: its asset lines, its liability lines and the derived ratios.
  #
  # Amounts are summed in Ruby from the per-line owned_* methods rather than through a
  # SQL SUM: total_assets/total_liabilities need an explicitly rounded SQL expression to
  # stay in step with BigDecimal, and summing the per-line values keeps these blocks
  # identical to what the views already display.
  PropertyPosition = Struct.new(:property, :asset_lines, :liability_lines, keyword_init: true) do
    def gross
      asset_lines.sum(&:owned_value)
    end

    # La dette qui pèse sur la valeur du bien : ses crédits, et eux seuls. Un dépôt de
    # garantie est bien une dette rattachée au bien, mais couverte par une trésorerie du
    # même montant que le bien ne porte pas (voir Liability::CASH_BACKED_TYPES) — d'où
    # #deposits, tenu à côté.
    def debt
      financing_lines.sum(&:owned_remaining_capital)
    end

    # Les dépôts de garantie du bien. Ils restent affichés — c'est une somme à rendre au
    # locataire, et le bien est le seul endroit où elle se lit — mais n'entrent ni dans la
    # valeur nette ni dans la LTV.
    def deposits
      deposit_lines.sum(&:owned_remaining_capital)
    end

    def net
      gross - debt
    end

    def ltv
      BalanceSheet.ltv_for(gross, debt)
    end

    def unassigned?
      property.nil?
    end

    private

    def financing_lines
      liability_lines.reject { |line| line.liability.cash_backed? }
    end

    def deposit_lines
      liability_lines.select { |line| line.liability.cash_backed? }
    end
  end

  # One row of the real-estate summary: an usage bucket or the overall total.
  # +ltv+ is derived once at build time (see #usage_total) rather than lazily.
  # +deposits+ is carried beside the three amounts and enters none of them, exactly as on
  # a single position (see PropertyPosition#deposits).
  UsageTotal = Struct.new(:gross, :debt, :net, :deposits, :ltv, keyword_init: true)

  # How one amount moved from the previous balance sheet to this one: the gain or loss in
  # euros, and the rate it represents. +rate+ is nil when the previous amount was zero —
  # there is no percentage to read on a move away from nothing, and the view renders the
  # euros alone rather than an infinite progression.
  Variation = Struct.new(:amount, :rate, keyword_init: true) do
    def gain?
      amount.positive?
    end

    def loss?
      amount.negative?
    end

    def flat?
      amount.zero?
    end
  end

  # Un bilan réduit à ses trois totaux, pour le tableau de bord : la courbe n'a besoin de
  # rien d'autre, et les recharger ligne à ligne pour tracer soixante points serait absurde.
  # Voir .timeline_for, qui les construit.
  TimelinePoint = Struct.new(:balance_sheet, :total_assets, :total_liabilities, keyword_init: true) do
    def closing_date
      balance_sheet.closing_date
    end

    def equity
      total_assets - total_liabilities
    end
  end

  # Une catégorie de la ventilation dans le temps : un montant par bilan, dans l'ordre où
  # les bilans ont été fournis. +key+ est stable et nomme la teinte que le CSS lui donne.
  #
  # Le libellé arrive en deux morceaux : +label+ nomme la grande famille, +sublabel+ l'usage
  # du bien quand la catégorie est éclatée, nil sinon. Les deux restent séparés jusqu'au bout
  # parce que la légende les met sur deux lignes — recomposer puis recouper une chaîne
  # traduite ferait dépendre la mise en page d'un séparateur. Voir .assets_breakdown_for.
  #
  # +sublabel_short+ est le même usage abrégé — « RP », « RS » — celui que la légende affiche :
  # sa colonne fait dix-neuf rems, « Résidence secondaire » y passait à la ligne. La forme
  # longue reste celle des infobulles et des textes accessibles, où la place ne manque pas.
  BreakdownSeries = Struct.new(:key, :label, :sublabel, :sublabel_short, :values, keyword_init: true) do
    def blank_everywhere?
      values.all?(&:zero?)
    end

    # Le libellé d'un seul tenant, là où il n'y a qu'une ligne à donner : l'infobulle d'une
    # bande du graphique.
    def full_label
      return label if sublabel.nil?

      I18n.t("views.shared.breakdown_split", type: label, usage: sublabel)
    end
  end

  # Les catégories de la ventilation dans le temps, dans l'ordre où elles s'empilent en
  # partant de l'axe. Trois familles à l'actif, et non une bande par type d'enum : un compte
  # courant, un livret et une créance répondent tous à la même question — de quoi dispose-t-on
  # tout de suite — et six bandes fines encombraient la courbe plus qu'elles ne la disaient.
  #
  # +split+ marque la seule catégorie qui garde son détail : l'immobilier, éclaté par usage du
  # bien, parce qu'une résidence principale, une secondaire et un locatif ne se pilotent pas
  # de la même façon. Le détail s'y lit à la nuance, jamais à la teinte.
  #
  # Seule cette catégorie-là est éclatée. Un compte courant rattaché à un bien reste une
  # liquidité : regrouper toutes les lignes d'un bien est le travail de l'onglet Immobilier
  # (voir #property_positions), pas celui d'une ventilation par catégorie.
  ASSET_CATEGORIES = [
    { key: "liquidity", types: %w[cash checking_account savings_account receivable] },
    { key: "real_estate", types: %w[real_estate], split: true },
    { key: "financial_investment", types: %w[financial_investment] }
  ].freeze

  # Le passif garde ses catégories d'origine, ordonnées en partant de l'axe : d'abord ce qui
  # n'est adossé à aucun bien — les dettes diverses, puis les autres crédits — puis les
  # dépôts de garantie, puis les crédits immobiliers et leur détail par usage.
  LIABILITY_CATEGORIES = [
    { key: "short_term_debt", types: %w[short_term_debt] },
    { key: "other_credit", types: %w[other_credit] },
    { key: "security_deposit", types: %w[security_deposit] },
    { key: "real_estate_loan", types: %w[real_estate_loan], split: true }
  ].freeze

  # L'ordre des usages à l'intérieur de l'immobilier. Il ne suit pas celui de l'enum mais celui
  # du dégradé qui les colore, de la résidence principale au locatif : la nuance ne peut dire
  # de quel usage il s'agit que si le rang, lui, ne bouge jamais.
  #
  # La liste ordonne, elle ne filtre pas (voir .breakdown_labels) : un usage ajouté à l'enum
  # sans passer par ici se range en queue, sans teinte attitrée, plutôt que de disparaître en
  # silence d'une courbe qui prétend montrer tout le patrimoine.
  BREAKDOWN_USAGE_ORDER = %w[primary_residence secondary_residence rental].freeze

  # La sous-catégorie des lignes immobilières qu'aucun bien ne porte encore.
  UNASSIGNED_USAGE = "unassigned".freeze

  # Liability types that belong to a property even when none is linked yet — les mêmes que
  # ceux qu'un bien peut porter, une seule liste pour les deux côtés du rattachement.
  UNASSIGNED_LIABILITY_TYPES = Liability::PROPERTY_LINKABLE_TYPES

  belongs_to :user
  has_many :balance_sheet_assets, dependent: :destroy
  has_many :balance_sheet_liabilities, dependent: :destroy
  has_many :assets, through: :balance_sheet_assets
  has_many :liabilities, through: :balance_sheet_liabilities

  validates :closing_date, presence: true
  validates :closing_date, uniqueness: { scope: :user_id }

  # Single definition of the loan-to-value, shared by a single position (PropertyPosition#ltv)
  # and by an usage bucket (#usage_total) so the two can never drift. It is a class method
  # only because PropertyPosition cannot reach a private instance method of BalanceSheet.
  # nil when there is no gross value to divide by — the view renders an em dash.
  def self.ltv_for(gross, debt)
    return nil if gross.zero?

    (debt / gross * 100).round(1)
  end

  # Single definition of a gain/perte between two amounts, shared by every variation the
  # synthèse displays. +to_d+ is not decorative: total_assets & co. return a plain Integer
  # when a sheet sums to zero, and an Integer division would silently floor the rate to 0.
  def self.variation_between(before, after)
    amount = after - before

    Variation.new(amount: amount, rate: before.zero? ? nil : (amount.to_d / before.abs * 100).round(1))
  end

  # Les trois totaux de chaque bilan de +sheets+, dans l'ordre où +sheets+ arrive.
  #
  # Deux requêtes agrégées pour toute la série, là où lire #total_assets / #total_liabilities
  # bilan par bilan en ferait deux PAR bilan : le tableau de bord trace l'historique complet,
  # et un utilisateur qui tient un bilan par mois depuis cinq ans en compte déjà soixante.
  #
  # Les expressions SQL sont celles des lignes elles-mêmes (BalanceSheetAsset::OWNED_VALUE_SQL),
  # pas une copie : la courbe du tableau de bord et la synthèse d'un même bilan ne peuvent donc
  # pas afficher deux montants différents. Un bilan sans aucune ligne n'a pas de groupe dans le
  # résultat du GROUP BY et retombe sur 0 — le même 0 que renvoient les totaux d'un bilan vide.
  def self.timeline_for(sheets)
    sheets = sheets.to_a
    return [] if sheets.empty?

    ids = sheets.map(&:id)
    assets = BalanceSheetAsset.joins(:asset).where(balance_sheet_id: ids)
      .group(:balance_sheet_id).sum(BalanceSheetAsset::OWNED_VALUE_SQL)
    liabilities = BalanceSheetLiability.joins(:liability).where(balance_sheet_id: ids)
      .group(:balance_sheet_id).sum(BalanceSheetLiability::OWNED_REMAINING_CAPITAL_SQL)

    sheets.map do |sheet|
      TimelinePoint.new(
        balance_sheet: sheet,
        total_assets: assets.fetch(sheet.id, 0),
        total_liabilities: liabilities.fetch(sheet.id, 0)
      )
    end
  end

  # La ventilation des actifs de +sheets+ dans le temps : une série par catégorie, chaque
  # série portant un montant par bilan. L'immobilier y est éclaté par usage du bien.
  #
  # Une seule requête agrégée pour toute la série, comme .timeline_for et pour la même
  # raison : le tableau de bord lit l'historique entier.
  def self.assets_breakdown_for(sheets)
    breakdown_for(
      sheets,
      scope: BalanceSheetAsset.joins(:asset).left_joins(asset: :property),
      type_column: "assets.asset_type",
      amount_sql: BalanceSheetAsset::OWNED_VALUE_SQL,
      types: Asset.asset_types,
      categories: ASSET_CATEGORIES
    )
  end

  # Le pendant pour la dette, les crédits immobiliers éclatés par usage du bien financé.
  def self.liabilities_breakdown_for(sheets)
    breakdown_for(
      sheets,
      scope: BalanceSheetLiability.joins(:liability).left_joins(liability: :property),
      type_column: "liabilities.liability_type",
      amount_sql: BalanceSheetLiability::OWNED_REMAINING_CAPITAL_SQL,
      types: Liability.liability_types,
      categories: LIABILITY_CATEGORIES
    )
  end

  # Les lignes de +source+ reprises sur ce bilan, et le nombre de celles qui ont été LAISSÉES
  # de côté : un actif ou un passif qui n'existe pas à la date de clôture d'arrivée n'y entre
  # pas (voir Lifespanable). Un PEE soldé en 2024 n'a rien à faire dans un bilan clos en 2026,
  # et le modèle le refuserait de toute façon — les recopier en bloc faisait échouer la
  # duplication entière sur la première ligne périmée.
  #
  # C'est bien un compte de lignes écartées qui remonte, et non un simple booléen : le
  # contrôleur le dit à l'utilisateur, une duplication qui perd des lignes en silence étant
  # indiscernable d'une duplication qui a raté.
  def copy_lines_from(source)
    skipped = 0

    transaction do
      source.balance_sheet_assets.includes(:asset).each do |line|
        next skipped += 1 unless line.asset.available_on?(closing_date)

        balance_sheet_assets.create!(asset_id: line.asset_id, value: line.value)
      end
      # Un prêt qui porte un tableau d'amortissement n'est pas recopié tel quel : son
      # capital restant dû est projeté à la date de clôture du nouveau bilan — recopier
      # l'ancien montant figerait la dette à une date où elle ne vaut plus cela. Les
      # passifs sans tableau gardent le comportement d'origine, la copie verbatim.
      source.balance_sheet_liabilities.includes(:liability).each do |line|
        next skipped += 1 unless line.liability.available_on?(closing_date)

        remaining_capital =
          if line.liability.amortizable?
            line.liability.suggested_remaining_capital(closing_date)
          else
            line.remaining_capital
          end

        balance_sheet_liabilities.create!(liability_id: line.liability_id, remaining_capital: remaining_capital)
      end
    end

    skipped
  end

  def total_assets
    balance_sheet_assets.joins(:asset).sum(BalanceSheetAsset::OWNED_VALUE_SQL)
  end

  def total_liabilities
    balance_sheet_liabilities.joins(:liability).sum(BalanceSheetLiability::OWNED_REMAINING_CAPITAL_SQL)
  end

  def equity
    total_assets - total_liabilities
  end

  def assets_by_risk_level
    balance_sheet_assets
      .includes(:asset)
      .joins(:asset)
      .order("assets.risk_level ASC, assets.name ASC")
      .group_by { |bsa| bsa.asset.risk_level }
  end

  def assets_by_type
    balance_sheet_assets
      .includes(:asset)
      .joins(:asset)
      .order("assets.asset_type ASC, assets.name ASC")
      .group_by { |bsa| bsa.asset.asset_type }
  end

  def liabilities_by_risk_level
    balance_sheet_liabilities
      .includes(:liability)
      .joins(:liability)
      .order("liabilities.risk_level ASC, liabilities.name ASC")
      .group_by { |bsl| bsl.liability.risk_level }
  end

  def liabilities_by_type
    balance_sheet_liabilities
      .includes(:liability)
      .joins(:liability)
      .order("liabilities.liability_type ASC, liabilities.name ASC")
      .group_by { |bsl| bsl.liability.liability_type }
  end

  # Every property holding at least one line on this balance sheet, ordered by usage
  # then name, followed by the "non rattaché" bucket when it has any line.
  def property_positions
    assets_by_property = property_asset_lines.group_by { |line| line.asset.property }
    liabilities_by_property = property_liability_lines.group_by { |line| line.liability.property }

    properties = (assets_by_property.keys + liabilities_by_property.keys).compact.uniq
    positions = properties
      .sort_by { |property| [Property.usages.fetch(property.usage), property.name] }
      .map do |property|
        PropertyPosition.new(
          property: property,
          asset_lines: assets_by_property.fetch(property, []),
          liability_lines: liabilities_by_property.fetch(property, [])
        )
      end

    unassigned = unassigned_position(assets_by_property[nil].to_a, liabilities_by_property[nil].to_a)
    positions << unassigned if unassigned

    positions
  end

  # Real-estate aggregates for the summary view: an ordered Hash of UsageTotal keyed by
  # usage string, then nil for the unassigned bucket, then :total for the overall row.
  #
  # +positions+ is a parameter because the controller passes in the FILTERED set (the
  # unassigned bucket rejected), so the rows the table displays and the totals it shows
  # are computed from the very same positions and cannot disagree.
  #
  # Les deux buckets portent les mêmes types, et par construction : seul l'actif immobilier
  # d'un bien et ses crédits immobiliers ou dépôts de garantie se rattachent à lui (voir
  # PropertyLinkable), et c'est exactement ce que le bucket « non rattaché » retient parmi
  # les lignes sans bien. Le bucket d'un bien n'a donc rien à filtrer par type.
  def real_estate_totals_by_usage(positions = property_positions)
    grouped = positions.group_by { |position| position.property&.usage }
    ordered_keys = grouped.keys.compact.sort_by { |usage| Property.usages.fetch(usage) }
    ordered_keys << nil if grouped.key?(nil)

    totals = ordered_keys.index_with { |usage| usage_total(grouped.fetch(usage)) }
    totals[:total] = usage_total(positions)
    totals
  end

  # The user's balance sheet immediately before this one, nil for the very first one.
  # Memoized through defined? because nil is a meaningful answer here: without it the very
  # first sheet would re-run the query on every variation the page asks for.
  def previous
    return @previous if defined?(@previous)

    @previous = user.balance_sheets.where("closing_date < ?", closing_date).order(closing_date: :desc).first
  end

  # Le bilan sur lequel se lit la variation « sur un an » : le plus récent qui ait au moins
  # un an de recul sur celui-ci. Une année calendaire et non 365 jours, pour qu'un bilan au
  # 31/12 se compare au 31/12 précédent même quand une année bissextile s'intercale — c'est
  # la lecture du tableau de bord d'accueil (DashboardController#point_a_year_before), et
  # les deux écrans doivent tomber sur le même bilan de référence.
  #
  # nil tant que l'historique ne remonte pas à un an : mieux vaut ne rien annoncer qu'une
  # progression mesurée sur trois mois présentée comme annuelle. Mémoïsé comme #previous,
  # nil étant ici une réponse à part entière.
  def year_ago
    return @year_ago if defined?(@year_ago)

    @year_ago = user.balance_sheets.where("closing_date <= ?", closing_date - 1.year)
      .order(closing_date: :desc).first
  end

  # The user's balance sheet immediately after this one, nil for the latest one. Only the
  # header navigation reads it — no variation is ever measured against it — but it is
  # memoized like #previous so a page asking twice queries once.
  def following
    return @following if defined?(@following)

    @following = user.balance_sheets.where("closing_date > ?", closing_date).order(closing_date: :asc).first
  end

  # The biens of this balance sheet, the "non rattaché" bucket left out: the immobilier tab
  # shows only the biens, and its totals — like its variations — are computed from these
  # very same positions so the rows and the totals can never disagree.
  def real_estate_positions
    property_positions.reject(&:unassigned?)
  end

  # The three headline figures of the synthèse tab read against +previous+.
  def variations_against(previous)
    {
      assets: self.class.variation_between(previous.total_assets, total_assets),
      liabilities: self.class.variation_between(previous.total_liabilities, total_liabilities),
      equity: self.class.variation_between(previous.equity, equity)
    }
  end

  # The whole patrimoine immobilier read against +previous+, on the valeur nette — the one
  # figure that says what it actually gained or lost, the brut and the dette moving for
  # reasons (revalorisation, amortissement) that only their difference summarises. The
  # per-usage and per-bien rows deliberately carry no variation: the tab reports the move
  # of the ensemble, not of each ligne.
  #
  # Both sides are read from #real_estate_positions, so the unassigned bucket is out of the
  # former total exactly as it is out of the current one — comparing a filtered total to an
  # unfiltered one would invent a gain or a perte out of the filtering alone.
  #
  # +positions+ is a parameter for the same reason as in #real_estate_totals_by_usage: the
  # controller hands in the very positions the table renders, so the amount and the
  # variation on the total row can never come from two different reads.
  def real_estate_variation_against(previous, positions = real_estate_positions)
    former = previous.real_estate_totals_by_usage(previous.real_estate_positions)

    self.class.variation_between(former[:total].net, real_estate_totals_by_usage(positions)[:total].net)
  end

  private

  def property_asset_lines
    balance_sheet_assets
      .includes(asset: :property)
      .joins(:asset)
      .order("assets.name ASC")
  end

  def property_liability_lines
    balance_sheet_liabilities
      .includes(liability: :property)
      .joins(:liability)
      .order("liabilities.name ASC")
  end

  # Lines that describe real estate but are not linked to a property yet.
  def unassigned_position(asset_lines, liability_lines)
    asset_lines = asset_lines.select { |line| line.asset.real_estate? }
    liability_lines = liability_lines.select { |line| UNASSIGNED_LIABILITY_TYPES.include?(line.liability.liability_type) }
    return nil if asset_lines.empty? && liability_lines.empty?

    PropertyPosition.new(property: nil, asset_lines: asset_lines, liability_lines: liability_lines)
  end

  # Le corps commun des deux ventilations. Le regroupement SQL descend jusqu'à l'usage du
  # bien, y compris pour les types qui ne sont pas éclatés : leurs lignes rattachées à des
  # biens différents reviennent alors sur plusieurs rangs, que l'accumulation ci-dessous
  # additionne sous la même catégorie.
  #
  # Les enums sont regroupés sur une colonne SQL qualifiée : selon la jointure, ActiveRecord
  # rend le nom déserialisé ou l'entier brut, d'où le passage par .enum_name.
  def self.breakdown_for(sheets, scope:, type_column:, amount_sql:, types:, categories:)
    sheets = sheets.to_a
    return [] if sheets.empty?

    # Chaque type d'enum tombe dans une catégorie et une seule. Le .fetch plus bas n'a pas de
    # repli : un type ajouté à l'enum sans être rangé ici doit casser la suite de tests, pas
    # disparaître en silence d'une courbe qui prétend montrer tout le patrimoine.
    category_of = categories.flat_map { |category| category[:types].map { |type| [type, category] } }.to_h
    index_of = sheets.each_with_index.to_h { |sheet, index| [sheet.id, index] }
    amounts = Hash.new { |hash, key| hash[key] = Array.new(sheets.size, 0) }

    scope.where(balance_sheet_id: sheets.map(&:id))
      .group(:balance_sheet_id, type_column, "properties.usage")
      .sum(amount_sql)
      .each do |(sheet_id, type_value, usage_value), amount|
        category = category_of.fetch(enum_name(types, type_value))
        key = breakdown_key(category, enum_name(Property.usages, usage_value))
        amounts[key][index_of.fetch(sheet_id)] += amount
      end

    breakdown_labels(categories)
      .select { |key, _| amounts.key?(key) }
      .map { |key, name, usage, usage_short|
        BreakdownSeries.new(key: key, label: name, sublabel: usage, sublabel_short: usage_short,
                            values: amounts[key])
      }
      .reject(&:blank_everywhere?)
  end
  private_class_method :breakdown_for

  def self.breakdown_key(category, usage)
    return category[:key] unless category[:split]

    "#{category[:key]}:#{usage || UNASSIGNED_USAGE}"
  end
  private_class_method :breakdown_key

  # Le nom d'une valeur d'enum, quelle que soit la forme sous laquelle elle revient du
  # regroupement : ActiveRecord la déserialise quand il sait rattacher la colonne groupée à
  # son modèle, et rend l'entier brut sinon. Parier sur l'une des deux formes marcherait
  # jusqu'au jour où la jointure change — d'où cette normalisation.
  def self.enum_name(values, value)
    return nil if value.nil?

    values.key?(value.to_s) ? value.to_s : values.key(value)
  end
  private_class_method :enum_name

  # Les [clé, famille, usage, usage abrégé] de chaque bande, dans l'ordre où elles s'empilent
  # en partant de l'axe : celui des catégories, la catégorie éclatée laissant place à ses usages
  # puis au bucket non rattaché. Un ordre figé, et surtout pas déduit des montants : une
  # catégorie qui changerait de rang — donc de couleur — d'un bilan à l'autre rendrait la
  # courbe illisible.
  #
  # Le bucket non rattaché n'a pas de forme courte à lui : son libellé sert des deux côtés.
  def self.breakdown_labels(categories)
    categories.flat_map do |category|
      label = I18n.t("views.shared.breakdown_categories.#{category[:key]}")
      next [[category[:key], label, nil, nil]] unless category[:split]

      usages = (BREAKDOWN_USAGE_ORDER | Property.usages.keys).map { |usage|
        [usage, Property.usage_label_for(usage), Property.usage_short_label_for(usage)]
      }
      unassigned = I18n.t("views.shared.unassigned_property")
      usages << [UNASSIGNED_USAGE, unassigned, unassigned]
      usages.map do |usage, usage_label, usage_short_label|
        ["#{category[:key]}:#{usage}", label, usage_label, usage_short_label]
      end
    end
  end
  private_class_method :breakdown_labels

  def usage_total(positions)
    gross = positions.sum(&:gross)
    debt = positions.sum(&:debt)

    UsageTotal.new(gross: gross, debt: debt, net: gross - debt,
                   deposits: positions.sum(&:deposits), ltv: self.class.ltv_for(gross, debt))
  end
end
