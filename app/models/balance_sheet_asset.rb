class BalanceSheetAsset < ApplicationRecord
  belongs_to :balance_sheet
  belongs_to :asset

  # Le montant détenu, tel que SQL le calcule. En constante parce que deux lectures s'en
  # servent — le total d'un bilan (BalanceSheet#total_assets) et la série chronologique de
  # tous les bilans (BalanceSheet.timeline_for) — et qu'un arrondi qui divergerait entre
  # les deux ferait dire deux montants différents au même bilan selon la page qui le lit.
  # L'arrondi de la quote-part avant la multiplication n'est pas décoratif : voir
  # BalanceSheet#total_assets.
  OWNED_VALUE_SQL = "ROUND(balance_sheet_assets.value * ROUND(assets.ownership_share / 100, 4), 2)".freeze

  validates :value, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :asset_id, uniqueness: { scope: :balance_sheet_id }

  def owned_value
    (value * asset.share_ratio).round(2)
  end
end
