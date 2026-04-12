FactoryBot.define do
  factory :balance_sheet_liability do
    balance_sheet
    liability
    remaining_capital { 5_000 }
  end
end
