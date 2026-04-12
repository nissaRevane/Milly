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
end
