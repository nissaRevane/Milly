class BalanceSheetLiability < ApplicationRecord
  belongs_to :balance_sheet
  belongs_to :liability

  validates :remaining_capital, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :liability_id, uniqueness: { scope: :balance_sheet_id }
end
