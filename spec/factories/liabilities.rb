FactoryBot.define do
  factory :liability do
    user
    sequence(:name) { |n| "Liability #{n}" }
    risk_level { :low }
    liability_type { :real_estate_loan }
    ownership_share { 100 }

    trait :amortizable do
      liability_type { :real_estate_loan }
      borrowed_capital { 200_000 }
      annual_rate { 3.0 }
      duration_months { 240 }
      monthly_payment { 1109.20 }
      first_payment_on { Date.new(2024, 3, 5) }
      first_payment_principal { 650.00 }
      first_payment_interest { 312.50 }
    end
  end
end
