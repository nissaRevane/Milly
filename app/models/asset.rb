class Asset < ApplicationRecord
  include RiskCategorizable

  belongs_to :user
  has_many :balance_sheet_assets, dependent: :destroy

  enum :asset_type, {
    cash: 0,
    checking_account: 1,
    savings_account: 2,
    financial_investment: 3,
    real_estate: 4,
    receivable: 5
  }, validate: true

  validates :name, presence: true

  def self.asset_type_label_for(type)
    return "" if type.blank?

    I18n.t("views.shared.asset_types.#{type}", default: type.to_s)
  end

  def asset_type_label
    self.class.asset_type_label_for(asset_type)
  end
end
