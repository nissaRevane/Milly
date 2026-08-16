class Asset < ApplicationRecord
  belongs_to :user
  has_many :balance_sheet_assets, dependent: :destroy

  enum :risk_level, { low: 0, medium: 1, high: 2 }
  enum :asset_type, { checking_account: 0, joint_account: 1, savings_account: 2, financial_investment: 3, real_estate: 4 }

  validates :name, presence: true
  validates :risk_level, presence: true
  validates :asset_type, presence: true

  RISK_LEVEL_LABELS = {
    "low" => "Faible",
    "medium" => "Moyen",
    "high" => "Élevé"
  }.freeze

  def risk_level_label
    RISK_LEVEL_LABELS[risk_level] || risk_level
  end

  def asset_type_label
    I18n.t("views.shared.asset_types.#{asset_type}")
  end
end
