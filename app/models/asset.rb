class Asset < ApplicationRecord
  belongs_to :user
  has_many :balance_sheet_assets, dependent: :destroy

  enum :risk_level, { low: 0, medium: 1, high: 2 }

  validates :name, presence: true
  validates :risk_level, presence: true

  RISK_LEVEL_LABELS = {
    "low" => "Faible",
    "medium" => "Moyen",
    "high" => "Élevé"
  }.freeze

  def risk_level_label
    RISK_LEVEL_LABELS[risk_level] || risk_level
  end
end
