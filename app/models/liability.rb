class Liability < ApplicationRecord
  include RiskCategorizable

  belongs_to :user
  has_many :balance_sheet_liabilities, dependent: :destroy

  validates :name, presence: true
end
