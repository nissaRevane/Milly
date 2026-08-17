class Property < ApplicationRecord
  belongs_to :user

  # :nullify, never :destroy — deleting a property must not erase the assets and
  # liabilities it grouped, otherwise the balance sheet history would lose lines.
  has_many :assets, dependent: :nullify
  has_many :liabilities, dependent: :nullify

  enum :usage, {
    primary_residence: 0,
    rental: 1,
    secondary_residence: 2
  }, validate: true

  # Unique per user because the name is the identity of a bien outside the database:
  # AccountExport references it by name and db/seeds.rb resolves it by name, so two
  # "Maison" would collapse into one on an export → import round trip.
  validates :name, presence: true, uniqueness: { scope: :user_id }

  def self.usage_label_for(usage)
    EnumLabel.for("property_usages", usage)
  end

  def usage_label
    self.class.usage_label_for(usage)
  end
end
