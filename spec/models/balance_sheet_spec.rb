require "rails_helper"

RSpec.describe BalanceSheet, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:balance_sheet_assets).dependent(:destroy) }
    it { is_expected.to have_many(:balance_sheet_liabilities).dependent(:destroy) }
    it { is_expected.to have_many(:assets).through(:balance_sheet_assets) }
    it { is_expected.to have_many(:liabilities).through(:balance_sheet_liabilities) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:closing_date) }

    it "validates uniqueness of closing_date scoped to user" do
      user = create(:user)
      create(:balance_sheet, user: user, closing_date: Date.today)
      duplicate = build(:balance_sheet, user: user, closing_date: Date.today)
      expect(duplicate).not_to be_valid
    end
  end

  describe "#total_assets" do
    it "sums up all balance sheet asset values" do
      bs = create(:balance_sheet)
      user = bs.user
      a1 = create(:asset, user: user)
      a2 = create(:asset, user: user)
      create(:balance_sheet_asset, balance_sheet: bs, asset: a1, value: 10_000)
      create(:balance_sheet_asset, balance_sheet: bs, asset: a2, value: 25_000)

      expect(bs.total_assets).to eq(35_000)
    end
  end

  describe "#total_liabilities" do
    it "sums up all balance sheet liability remaining capitals" do
      bs = create(:balance_sheet)
      user = bs.user
      l1 = create(:liability, user: user)
      l2 = create(:liability, user: user)
      create(:balance_sheet_liability, balance_sheet: bs, liability: l1, remaining_capital: 5_000)
      create(:balance_sheet_liability, balance_sheet: bs, liability: l2, remaining_capital: 15_000)

      expect(bs.total_liabilities).to eq(20_000)
    end
  end

  describe "#equity" do
    it "returns total_assets minus total_liabilities" do
      bs = create(:balance_sheet)
      user = bs.user
      asset = create(:asset, user: user)
      liability = create(:liability, user: user)
      create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 100_000)
      create(:balance_sheet_liability, balance_sheet: bs, liability: liability, remaining_capital: 60_000)

      expect(bs.equity).to eq(40_000)
    end
  end
end
