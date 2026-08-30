class BalanceSheetLiability < ApplicationRecord
  belongs_to :balance_sheet
  belongs_to :liability

  # Le pendant de BalanceSheetAsset::OWNED_VALUE_SQL pour la dette, et pour les mêmes
  # raisons : une seule définition, partagée par le total d'un bilan et par la série.
  OWNED_REMAINING_CAPITAL_SQL =
    "ROUND(balance_sheet_liabilities.remaining_capital * ROUND(liabilities.ownership_share / 100, 4), 2)".freeze

  validates :remaining_capital, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :liability_id, uniqueness: { scope: :balance_sheet_id }

  # Le pendant de BalanceSheetAsset#asset_within_its_lifespan, pour les mêmes raisons :
  # une dette éteinte ou pas encore née n'entre pas dans un bilan clos hors de sa période.
  validate :liability_within_its_lifespan, on: :create

  # Le pendant de BalanceSheetAsset#asset_belongs_to_the_same_account, pour les mêmes
  # raisons : une dette forgée appartenant à un autre compte fuirait son nom et son bien.
  validate :liability_belongs_to_the_same_account

  def owned_remaining_capital
    (remaining_capital * liability.share_ratio).round(2)
  end

  delegate :category_key, to: :liability

  private

  def liability_belongs_to_the_same_account
    return if liability.nil? || balance_sheet.nil?
    return if liability.user_id == balance_sheet.user_id

    errors.add(:liability, :invalid)
  end

  def liability_within_its_lifespan
    return if liability.nil? || balance_sheet.nil?
    return if liability.available_on?(balance_sheet.closing_date)

    errors.add(:liability, :outside_lifespan)
  end
end
