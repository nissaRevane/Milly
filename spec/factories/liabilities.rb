FactoryBot.define do
  factory :liability do
    user
    sequence(:name) { |n| "Liability #{n}" }
    risk_level { :low }
  end
end
