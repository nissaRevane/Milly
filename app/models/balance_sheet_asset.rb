class BalanceSheetAsset < ApplicationRecord
  belongs_to :balance_sheet
  belongs_to :asset

  validates :value, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :asset_id, uniqueness: { scope: :balance_sheet_id }
end
