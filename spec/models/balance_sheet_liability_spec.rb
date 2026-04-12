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
end
