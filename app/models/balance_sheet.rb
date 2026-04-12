class BalanceSheet < ApplicationRecord
  belongs_to :user
  has_many :balance_sheet_assets, dependent: :destroy
  has_many :balance_sheet_liabilities, dependent: :destroy
  has_many :assets, through: :balance_sheet_assets
  has_many :liabilities, through: :balance_sheet_liabilities

  validates :closing_date, presence: true
  validates :closing_date, uniqueness: { scope: :user_id }

  def total_assets
    balance_sheet_assets.sum(:value)
  end

  def total_liabilities
    balance_sheet_liabilities.sum(:remaining_capital)
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

  def liabilities_by_risk_level
    balance_sheet_liabilities
      .includes(:liability)
      .joins(:liability)
      .order("liabilities.risk_level ASC, liabilities.name ASC")
      .group_by { |bsl| bsl.liability.risk_level }
  end
end
