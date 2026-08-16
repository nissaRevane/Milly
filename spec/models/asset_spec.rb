require "rails_helper"

RSpec.describe Asset, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:balance_sheet_assets).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:risk_level) }
    it { is_expected.to validate_presence_of(:asset_type) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:risk_level).with_values(low: 0, medium: 1, high: 2) }
    it {
      is_expected.to define_enum_for(:asset_type).with_values(
        checking_account: 0, joint_account: 1, savings_account: 2, financial_investment: 3, real_estate: 4
      )
    }
  end

  describe "#risk_level_label" do
    it "returns the French label for the risk level" do
      asset = build(:asset, risk_level: :medium)
      expect(asset.risk_level_label).to eq("Moyen")
    end
  end

  describe "#asset_type_label" do
    it "returns the French label for the asset type" do
      asset = build(:asset, asset_type: :savings_account)
      expect(asset.asset_type_label).to eq("Compte épargne")
    end
  end
end
