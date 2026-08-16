module Shareable
  extend ActiveSupport::Concern

  included do
    validates :ownership_share,
              presence: true,
              numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100, allow_nil: true }
  end

  # Fraction of the registered value actually owned, e.g. 50.0 -> 0.5
  def share_ratio
    ownership_share / 100
  end

  def full_ownership?
    ownership_share == 100
  end
end
