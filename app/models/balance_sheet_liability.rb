class BalanceSheetLiability < ApplicationRecord
  belongs_to :balance_sheet
  belongs_to :liability

  # Le pendant de BalanceSheetAsset::OWNED_VALUE_SQL pour la dette, et pour les mêmes
  # raisons : une seule définition, partagée par le total d'un bilan et par la série.
  OWNED_REMAINING_CAPITAL_SQL =
    "ROUND(balance_sheet_liabilities.remaining_capital * ROUND(liabilities.ownership_share / 100, 4), 2)".freeze

  validates :remaining_capital, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :liability_id, uniqueness: { scope: :balance_sheet_id }

  def owned_remaining_capital
    (remaining_capital * liability.share_ratio).round(2)
  end
end
