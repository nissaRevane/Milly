FactoryBot.define do
  factory :liability do
    user
    sequence(:name) { |n| "Liability #{n}" }
    risk_level { :low }
    liability_type { :real_estate_loan }
    ownership_share { 100 }
  end
end
