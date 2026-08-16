module RiskCategorizable
  extend ActiveSupport::Concern

  RISK_LEVELS = { low: 0, medium: 1, high: 2 }.freeze

  included do
    enum :risk_level, RISK_LEVELS, validate: true
  end

  def self.label_for(level)
    EnumLabel.for("risk_levels", level)
  end

  def risk_level_label
    RiskCategorizable.label_for(risk_level)
  end
end
