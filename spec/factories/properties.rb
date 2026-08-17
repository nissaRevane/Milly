FactoryBot.define do
  factory :property do
    user
    sequence(:name) { |n| "Property #{n}" }
    usage { :primary_residence }
  end
end
