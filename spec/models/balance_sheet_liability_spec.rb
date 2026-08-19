require "rails_helper"

RSpec.describe BalanceSheetLiability, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:balance_sheet) }
    it { is_expected.to belong_to(:liability) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:remaining_capital) }
    it { is_expected.to validate_numericality_of(:remaining_capital).is_greater_than_or_equal_to(0) }

    # Le pendant de BalanceSheetAsset : voir son spec pour le détail de la tolérance.
    it "rejects a liability that did not exist yet at the closing date" do
      bs = create(:balance_sheet, closing_date: Date.new(2025, 3, 31))
      liability = create(:liability, user: bs.user, started_on: Date.new(2025, 5, 1))
      line = build(:balance_sheet_liability, balance_sheet: bs, liability: liability)

      expect(line).not_to be_valid
      expect(line.errors[:liability]).to eq(["n'existait pas à la date de ce bilan"])
    end

    it "accepts a liability repaid anywhere in the month of the closing date" do
      bs = create(:balance_sheet, closing_date: Date.new(2025, 3, 31))
      liability = create(:liability, user: bs.user, ended_on: Date.new(2025, 3, 2))

      expect(build(:balance_sheet_liability, balance_sheet: bs, liability: liability)).to be_valid
    end

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
