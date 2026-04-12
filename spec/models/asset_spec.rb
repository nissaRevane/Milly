require "rails_helper"

RSpec.describe Asset, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:balance_sheet_assets).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:risk_level) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:risk_level).with_values(low: 0, medium: 1, high: 2) }
  end

  describe "#risk_level_label" do
    it "returns the French label for the risk level" do
      asset = build(:asset, risk_level: :medium)
      expect(asset.risk_level_label).to eq("Moyen")
    end
  end
end
