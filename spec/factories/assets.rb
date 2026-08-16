FactoryBot.define do
  factory :asset do
    user
    sequence(:name) { |n| "Asset #{n}" }
    risk_level { :low }
    asset_type { :checking_account }
    ownership_share { 100 }
  end
end
