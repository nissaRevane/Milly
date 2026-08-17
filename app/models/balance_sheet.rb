class BalanceSheet < ApplicationRecord
  belongs_to :user
  has_many :balance_sheet_assets, dependent: :destroy
  has_many :balance_sheet_liabilities, dependent: :destroy
  has_many :assets, through: :balance_sheet_assets
  has_many :liabilities, through: :balance_sheet_liabilities

  validates :closing_date, presence: true
  validates :closing_date, uniqueness: { scope: :user_id }

  def copy_lines_from(source)
    transaction do
      source.balance_sheet_assets.each do |line|
        balance_sheet_assets.create!(asset_id: line.asset_id, value: line.value)
      end
      source.balance_sheet_liabilities.each do |line|
        balance_sheet_liabilities.create!(liability_id: line.liability_id, remaining_capital: line.remaining_capital)
      end
    end
  end

  def total_assets
    balance_sheet_assets
      .joins(:asset)
      .sum("ROUND(balance_sheet_assets.value * ROUND(assets.ownership_share / 100, 4), 2)")
  end

  def total_liabilities
    balance_sheet_liabilities
      .joins(:liability)
      .sum("ROUND(balance_sheet_liabilities.remaining_capital * ROUND(liabilities.ownership_share / 100, 4), 2)")
  end

  def equity
    total_assets - total_liabilities
  end

  def assets_by_risk_level
    balance_sheet_assets
      .includes(:asset)
      .joins(:asset)
      .order("assets.risk_level ASC, assets.name ASC")
      .group_by { |bsa| bsa.asset.risk_level }
  end

  def assets_by_type
    balance_sheet_assets
      .includes(:asset)
      .joins(:asset)
      .order("assets.asset_type ASC, assets.name ASC")
      .group_by { |bsa| bsa.asset.asset_type }
  end

  def liabilities_by_risk_level
    balance_sheet_liabilities
      .includes(:liability)
      .joins(:liability)
      .order("liabilities.risk_level ASC, liabilities.name ASC")
      .group_by { |bsl| bsl.liability.risk_level }
  end

  def liabilities_by_type
    balance_sheet_liabilities
      .includes(:liability)
      .joins(:liability)
      .order("liabilities.liability_type ASC, liabilities.name ASC")
      .group_by { |bsl| bsl.liability.liability_type }
  end
end
