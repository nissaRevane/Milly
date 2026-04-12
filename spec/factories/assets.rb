FactoryBot.define do
  factory :asset do
    user
    sequence(:name) { |n| "Asset #{n}" }
    risk_level { :low }
  end
end
