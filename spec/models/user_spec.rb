require "rails_helper"

RSpec.describe User, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:assets).dependent(:destroy) }
    it { is_expected.to have_many(:liabilities).dependent(:destroy) }
    it { is_expected.to have_many(:balance_sheets).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:firstname) }
    it { is_expected.to validate_presence_of(:lastname) }
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_presence_of(:password) }
  end

  describe "#full_name" do
    it "returns firstname and lastname" do
      user = build(:user, firstname: "Jean", lastname: "Dupont")
      expect(user.full_name).to eq("Jean Dupont")
    end
  end
end
