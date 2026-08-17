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

  def asset_type_options
    Asset.asset_types.keys.map { |key| [t("views.shared.asset_types.#{key}"), key] }
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

  # The unassigned bucket is keyed by nil in both property_positions and
  # real_estate_totals_by_usage: it gets the "non rattaché" wording, not an usage label.
  def property_bucket_label(usage)
    usage.presence ? property_usage_label(usage) : t("views.balance_sheets.properties.unassigned")
  end

  # An LTV is nil whenever the ratio would be meaningless (no gross value, or the
  # overall total that mixes usages) — an em dash reads better than a blank cell.
  def ltv_label(ltv)
    return "—" if ltv.nil?

    number_to_percentage(ltv, precision: 1)
  end

  def ownership_share_label(share)
    precision = (share.to_d % 1).zero? ? 0 : 2
    number_to_percentage(share, precision: precision)
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
