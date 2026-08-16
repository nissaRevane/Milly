class Liability < ApplicationRecord
  include RiskCategorizable
  include Shareable

  belongs_to :user
  has_many :balance_sheet_liabilities, dependent: :destroy

  enum :liability_type, {
    real_estate_loan: 0,
    short_term_debt: 1,
    security_deposit: 2
  }, validate: true

  validates :name, presence: true

  def self.liability_type_label_for(type)
    EnumLabel.for("liability_types", type)
  end

  def liability_type_label
    self.class.liability_type_label_for(liability_type)
  end
end
