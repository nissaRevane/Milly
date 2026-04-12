FactoryBot.define do
  factory :balance_sheet do
    user
    closing_date { Date.today }
  end
end
