module ApplicationHelper
  def risk_level_options
    RiskCategorizable::RISK_LEVELS.keys.map { |key| [t("views.shared.risk_levels.#{key}"), key] }
  end

  def risk_level_label(level)
    RiskCategorizable.label_for(level)
  end

  def risk_level_badge_class(level)
    case level
    when "low" then "badge-success"
    when "medium" then "badge-warning"
    when "high" then "badge-danger"
    else "badge-secondary"
    end
  end

  # Every type, for the index filter: immobilier lines exist and must be filterable.
  def asset_type_options
    Asset.asset_types.keys.map { |key| [t("views.shared.asset_types.#{key}"), key] }
  end

  # What the form offers: immobilier is left out, it comes from creating a bien.
  def selectable_asset_type_options
    Asset.selectable_asset_types.map { |key| [t("views.shared.asset_types.#{key}"), key] }
  end

  def asset_type_label(type)
    Asset.asset_type_label_for(type)
  end

  def liability_type_options
    Liability.liability_types.keys.map { |key| [t("views.shared.liability_types.#{key}"), key] }
  end

  # Les types de passifs qu'un bien porte réellement, tels que le contrôleur Stimulus les
  # lit : une liste séparée par des espaces, dans l'attribut data du bloc à montrer.
  def property_linkable_liability_types
    Liability::PROPERTY_LINKABLE_TYPES.join(" ")
  end

  # Les types de passifs qui portent un tableau d'amortissement, dans la même forme lue par
  # le contrôleur Stimulus : une liste séparée par des espaces.
  def amortizable_liability_types
    Liability::AMORTIZABLE_TYPES.join(" ")
  end

  def liability_type_label(type)
    Liability.liability_type_label_for(type)
  end

  def property_usage_options
    Property.usages.keys.map { |key| [t("views.shared.property_usages.#{key}"), key] }
  end

  # La pastille d'usage d'un bien. Elle porte les DEUX formes du libellé : le complet comme
  # texte, l'abrégé en attribut, et c'est le CSS qui décide lequel se voit selon la largeur
  # (voir .usage-badge) — « Résidence principale » débordait de la pastille sur un écran
  # étroit, « RP » y tient.
  #
  # Le texte de l'élément reste le libellé complet à toute largeur, l'abréviation n'étant que
  # du contenu généré : le nom accessible, la recherche dans la page et le copier-coller
  # continuent de dire « Résidence principale » là où l'œil ne lit que « RP », et le title le
  # rend au survol. Un usage dont la forme courte est déjà la longue — « Locatif » — sort en
  # pastille ordinaire, il n'y a rien à substituer.
  def property_usage_badge(usage)
    full = Property.usage_label_for(usage)
    short = Property.usage_short_label_for(usage)
    return tag.span(full, class: "badge badge-secondary") if short == full

    tag.span(full, class: "badge badge-secondary usage-badge", title: full,
                   data: { usage_short: short })
  end

  # An LTV is nil only when there is no gross value to divide by — an em dash
  # reads better than a blank cell.
  def ltv_label(ltv)
    return "—" if ltv.nil?

    number_to_percentage(ltv, precision: 1)
  end

  # The gain/perte of an amount against the previous balance sheet, as a small note to hang
  # under (or next to) the amount it qualifies. Renders nothing at all when +variation+ is
  # nil — the very first balance sheet has no predecessor to read an evolution against.
  #
  # +favorable+ says which direction reads as good news, because the sign alone does not:
  # the passifs column passes :down, a dette going down being the favourable move there.
  # The colour follows that reading, the sign always follows the actual amount.
  def variation_note(variation, favorable: :up)
    return nil if variation.nil?

    tag.span(variation_label(variation), class: "variation variation-#{variation_tone(variation, favorable)}")
  end

  def ownership_share_label(share)
    precision = (share.to_d % 1).zero? ? 0 : 2
    number_to_percentage(share, precision: precision)
  end

  # La valeur suggérée telle qu'un <input type="number"> l'accepte, nil quand il n'y en a
  # pas : point décimal (to_s("F"), la notation par défaut de BigDecimal est
  # scientifique), et pas de « ,0 » parasite affiché quand le montant est rond.
  def suggested_value_attribute(value)
    return nil if value.nil?

    value.frac.zero? ? value.to_i.to_s : value.to_s("F")
  end

  # Les attributs data d'un champ qui s'édite sur place : Échap annule, quitter le champ
  # enregistre si la valeur a changé (voir le contrôleur Stimulus inline-edit). Ils sont
  # rendus par un helper parce que chaque fiche en pose une dizaine : recopiée à la main,
  # la chaîne d'actions finissait par différer d'un champ à l'autre.
  #
  # +on_change+ pour un select : il se valide au choix d'une option, sans attendre un blur
  # qui ne viendra pas.
  def inline_edit_input_data(on_change: false)
    actions = ["keydown.esc->inline-edit#cancel:prevent", "blur->inline-edit#blur"]
    actions.unshift("change->inline-edit#submit") if on_change

    { inline_edit_target: "input", action: actions.join(" ") }
  end

  def owned_value_cell(total_value, owned_value, share)
    return number_to_currency(owned_value) if share.to_d == 100

    safe_join([
      number_to_currency(owned_value),
      tag.span(
        t("views.shared.owned_value_detail",
          share: ownership_share_label(share),
          total: number_to_currency(total_value)),
        class: "owned-value-detail"
      )
    ])
  end

  private

  # Amounts and rates are formatted from their absolute value with an explicit sign, so a
  # gain reads "+12 000 €" where number_to_currency alone would only ever mark the losses.
  # Les centimes d'une variation ne disent rien : le montant est arrondi à l'euro, ce qui
  # raccourcit d'autant la note — elle tient dans les tuiles étroites du tableau de bord.
  # The rate is dropped when there is none: nothing to divide by (see BalanceSheet::Variation).
  #
  # Le montant et le taux sont deux spans distincts : chacun reste insécable, mais la note
  # peut passer à la ligne entre les deux plutôt que de déborder de sa tuile.
  def variation_label(variation)
    sign = variation.flat? ? "" : (variation.gain? ? "+" : "-")
    amount = tag.span("#{sign}#{number_to_currency(variation.amount.abs, precision: 0)}",
                      class: "variation-amount")
    return amount if variation.rate.nil?

    rate = tag.span("(#{sign}#{number_to_percentage(variation.rate.abs, precision: 1)})",
                    class: "variation-rate")
    safe_join([amount, rate], " ")
  end

  def variation_tone(variation, favorable)
    return "flat" if variation.flat?

    (favorable == :down ? variation.loss? : variation.gain?) ? "gain" : "loss"
  end
end
