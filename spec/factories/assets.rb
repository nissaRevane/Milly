FactoryBot.define do
  factory :asset do
    user
    sequence(:name) { |n| "Asset #{n}" }
    asset_type { :checking_account }
    ownership_share { 100 }
  end
end
