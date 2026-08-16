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

  def ownership_share_label(share)
    precision = (share.to_d % 1).zero? ? 0 : 2
    number_to_percentage(share, precision: precision)
  end
end
