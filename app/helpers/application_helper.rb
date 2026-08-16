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
end
