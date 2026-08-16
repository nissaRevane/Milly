require "rails_helper"

RSpec.describe BalanceSheetAsset, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:balance_sheet) }
    it { is_expected.to belong_to(:asset) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:value) }
    it { is_expected.to validate_numericality_of(:value).is_greater_than_or_equal_to(0) }

    it "validates uniqueness of asset_id scoped to balance_sheet" do
      bs = create(:balance_sheet)
      asset = create(:asset, user: bs.user)
      create(:balance_sheet_asset, balance_sheet: bs, asset: asset)
      duplicate = build(:balance_sheet_asset, balance_sheet: bs, asset: asset)
      expect(duplicate).not_to be_valid
    end
  end

  describe "#owned_value" do
    let(:bs) { create(:balance_sheet) }

    it "returns the full value when the asset is fully owned" do
      asset = create(:asset, user: bs.user, ownership_share: 100)
      bsa = create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 10_000)

      expect(bsa.owned_value).to eq(10_000)
    end

    it "returns half the value when the asset is owned at 50%" do
      asset = create(:asset, user: bs.user, ownership_share: 50)
      bsa = create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 10_000)

      expect(bsa.owned_value).to eq(5_000)
    end

    it "rounds the owned value to two decimals" do
      asset = create(:asset, user: bs.user, ownership_share: 33.33)
      bsa = create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 1_001.55)

      expect(bsa.owned_value).to eq(BigDecimal("333.82"))
    end
  end
end
