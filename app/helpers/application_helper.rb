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

  def liability_type_label(type)
    Liability.liability_type_label_for(type)
  end

  def property_usage_options
    Property.usages.keys.map { |key| [t("views.shared.property_usages.#{key}"), key] }
  end

  def property_usage_label(usage)
    Property.usage_label_for(usage)
  end

  # An LTV is nil whenever the ratio would be meaningless (no gross value) — an em
  # dash reads better than a blank cell.
  def ltv_label(ltv)
    return "—" if ltv.nil?

    number_to_percentage(ltv, precision: 1)
  end

  def ownership_share_label(share)
    precision = (share.to_d % 1).zero? ? 0 : 2
    number_to_percentage(share, precision: precision)
  end

  # La valeur suggérée telle qu'un <input type="number"> l'accepte, nil quand il n'y en a
  # pas : point décimal, et pas de « ,0 » parasite affiché quand le montant est rond.
  def suggested_value_attribute(asset)
    value = asset.suggested_value
    return nil if value.nil?

    value.frac.zero? ? value.to_i.to_s : value.to_s
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
end
