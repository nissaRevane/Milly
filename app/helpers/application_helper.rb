module ApplicationHelper
  def risk_level_options
    [
      [t("views.shared.risk_levels.low"), "low"],
      [t("views.shared.risk_levels.medium"), "medium"],
      [t("views.shared.risk_levels.high"), "high"]
    ]
  end

  def risk_level_label(level)
    {
      "low" => t("views.shared.risk_levels.low"),
      "medium" => t("views.shared.risk_levels.medium"),
      "high" => t("views.shared.risk_levels.high")
    }[level] || level
  end

  def asset_type_options
    Asset.asset_types.keys.map { |key| [t("views.shared.asset_types.#{key}"), key] }
  end

  def risk_level_badge_class(level)
    case level
    when "low" then "badge-success"
    when "medium" then "badge-warning"
    when "high" then "badge-danger"
    else "badge-secondary"
    end
  end
end
