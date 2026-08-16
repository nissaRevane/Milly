require "rails_helper"

RSpec.describe BalanceSheetLiability, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:balance_sheet) }
    it { is_expected.to belong_to(:liability) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:remaining_capital) }
    it { is_expected.to validate_numericality_of(:remaining_capital).is_greater_than_or_equal_to(0) }

    it "validates uniqueness of liability_id scoped to balance_sheet" do
      bs = create(:balance_sheet)
      liability = create(:liability, user: bs.user)
      create(:balance_sheet_liability, balance_sheet: bs, liability: liability)
      duplicate = build(:balance_sheet_liability, balance_sheet: bs, liability: liability)
      expect(duplicate).not_to be_valid
    end
  end

  describe "#owned_remaining_capital" do
    let(:bs) { create(:balance_sheet) }

    it "returns the full remaining capital when the liability is fully owned" do
      liability = create(:liability, user: bs.user, ownership_share: 100)
      bsl = create(:balance_sheet_liability, balance_sheet: bs, liability: liability, remaining_capital: 5_000)

      expect(bsl.owned_remaining_capital).to eq(5_000)
    end

    it "returns half the remaining capital when the liability is owned at 50%" do
      liability = create(:liability, user: bs.user, ownership_share: 50)
      bsl = create(:balance_sheet_liability, balance_sheet: bs, liability: liability, remaining_capital: 5_000)

      expect(bsl.owned_remaining_capital).to eq(2_500)
    end

    it "rounds the owned remaining capital to two decimals" do
      liability = create(:liability, user: bs.user, ownership_share: 33.33)
      bsl = create(:balance_sheet_liability, balance_sheet: bs, liability: liability, remaining_capital: 1_001.55)

      expect(bsl.owned_remaining_capital).to eq(BigDecimal("333.82"))
    end
  end
end
