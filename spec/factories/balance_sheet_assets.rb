FactoryBot.define do
  factory :balance_sheet_asset do
    balance_sheet
    asset
    value { 10_000 }
  end
end
