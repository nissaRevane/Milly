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
    it "sums up all balance sheet asset values when everything is fully owned" do
      bs = create(:balance_sheet)
      user = bs.user
      a1 = create(:asset, user: user, ownership_share: 100)
      a2 = create(:asset, user: user, ownership_share: 100)
      create(:balance_sheet_asset, balance_sheet: bs, asset: a1, value: 10_000)
      create(:balance_sheet_asset, balance_sheet: bs, asset: a2, value: 25_000)

      expect(bs.total_assets).to eq(35_000)
    end

    it "only counts the owned share of partially owned assets" do
      bs = create(:balance_sheet)
      user = bs.user
      full = create(:asset, user: user, ownership_share: 100)
      half = create(:asset, user: user, ownership_share: 50)
      quarter = create(:asset, user: user, ownership_share: 25)
      create(:balance_sheet_asset, balance_sheet: bs, asset: full, value: 10_000)
      create(:balance_sheet_asset, balance_sheet: bs, asset: half, value: 25_000)
      create(:balance_sheet_asset, balance_sheet: bs, asset: quarter, value: 8_000)

      expect(bs.total_assets).to eq(10_000 + 12_500 + 2_000)
    end

    it "equals the sum of the per-line owned values, even with an uneven share" do
      bs = create(:balance_sheet)
      user = bs.user
      a1 = create(:asset, user: user, ownership_share: 33.33)
      a2 = create(:asset, user: user, ownership_share: 33.33)
      create(:balance_sheet_asset, balance_sheet: bs, asset: a1, value: 1_001.55)
      create(:balance_sheet_asset, balance_sheet: bs, asset: a2, value: 2_002.45)

      expected = bs.balance_sheet_assets.sum(&:owned_value)

      expect(expected).to eq(BigDecimal("333.82") + BigDecimal("667.42"))
      expect(bs.total_assets).to eq(expected)
    end

    it "rounds exactly like the per-line owned value near the decimal(15,2) ceiling" do
      bs = create(:balance_sheet)
      user = bs.user
      asset = create(:asset, user: user, ownership_share: 47.69)
      create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: BigDecimal("2914957409237.23"))

      expected = bs.balance_sheet_assets.sum(&:owned_value)

      expect(expected).to eq(BigDecimal("1390143188465.23"))
      expect(bs.total_assets).to eq(expected)
    end
  end

  describe "#total_liabilities" do
    it "sums up all balance sheet liability remaining capitals when everything is fully owned" do
      bs = create(:balance_sheet)
      user = bs.user
      l1 = create(:liability, user: user, ownership_share: 100)
      l2 = create(:liability, user: user, ownership_share: 100)
      create(:balance_sheet_liability, balance_sheet: bs, liability: l1, remaining_capital: 5_000)
      create(:balance_sheet_liability, balance_sheet: bs, liability: l2, remaining_capital: 15_000)

      expect(bs.total_liabilities).to eq(20_000)
    end

    it "only counts the owned share of partially owned liabilities" do
      bs = create(:balance_sheet)
      user = bs.user
      full = create(:liability, user: user, ownership_share: 100)
      half = create(:liability, user: user, ownership_share: 50)
      create(:balance_sheet_liability, balance_sheet: bs, liability: full, remaining_capital: 5_000)
      create(:balance_sheet_liability, balance_sheet: bs, liability: half, remaining_capital: 15_000)

      expect(bs.total_liabilities).to eq(5_000 + 7_500)
    end

    it "equals the sum of the per-line owned remaining capitals, even with an uneven share" do
      bs = create(:balance_sheet)
      user = bs.user
      l1 = create(:liability, user: user, ownership_share: 33.33)
      l2 = create(:liability, user: user, ownership_share: 33.33)
      create(:balance_sheet_liability, balance_sheet: bs, liability: l1, remaining_capital: 1_001.55)
      create(:balance_sheet_liability, balance_sheet: bs, liability: l2, remaining_capital: 2_002.45)

      expected = bs.balance_sheet_liabilities.sum(&:owned_remaining_capital)

      expect(expected).to eq(BigDecimal("333.82") + BigDecimal("667.42"))
      expect(bs.total_liabilities).to eq(expected)
    end

    it "rounds exactly like the per-line owned remaining capital near the decimal(15,2) ceiling" do
      bs = create(:balance_sheet)
      user = bs.user
      liability = create(:liability, user: user, ownership_share: 47.69)
      create(:balance_sheet_liability, balance_sheet: bs, liability: liability, remaining_capital: BigDecimal("2914957409237.23"))

      expected = bs.balance_sheet_liabilities.sum(&:owned_remaining_capital)

      expect(expected).to eq(BigDecimal("1390143188465.23"))
      expect(bs.total_liabilities).to eq(expected)
    end
  end

  describe "#assets_by_type" do
    it "groups assets under their type key, ordered by type" do
      bs = create(:balance_sheet)
      user = bs.user
      immo = create(:asset, user: user, name: "Maison", asset_type: :real_estate)
      cash = create(:asset, user: user, name: "Espèces", asset_type: :cash)
      livret = create(:asset, user: user, name: "Livret A", asset_type: :savings_account)
      create(:balance_sheet_asset, balance_sheet: bs, asset: immo, value: 100_000)
      create(:balance_sheet_asset, balance_sheet: bs, asset: cash, value: 500)
      create(:balance_sheet_asset, balance_sheet: bs, asset: livret, value: 2_000)

      grouped = bs.assets_by_type

      expect(grouped.keys).to eq(["cash", "savings_account", "real_estate"])
      expect(grouped["cash"].map { |bsa| bsa.asset.name }).to eq(["Espèces"])
      expect(grouped["savings_account"].map { |bsa| bsa.asset.name }).to eq(["Livret A"])
      expect(grouped["real_estate"].map { |bsa| bsa.asset.name }).to eq(["Maison"])
    end
  end

  describe "#liabilities_by_type" do
    it "groups liabilities under their type key, ordered by type" do
      bs = create(:balance_sheet)
      user = bs.user
      deposit = create(:liability, user: user, name: "Caution", liability_type: :security_deposit)
      loan = create(:liability, user: user, name: "Prêt maison", liability_type: :real_estate_loan)
      short = create(:liability, user: user, name: "Découvert", liability_type: :short_term_debt)
      create(:balance_sheet_liability, balance_sheet: bs, liability: deposit, remaining_capital: 800)
      create(:balance_sheet_liability, balance_sheet: bs, liability: loan, remaining_capital: 150_000)
      create(:balance_sheet_liability, balance_sheet: bs, liability: short, remaining_capital: 1_200)

      grouped = bs.liabilities_by_type

      expect(grouped.keys).to eq(["real_estate_loan", "short_term_debt", "security_deposit"])
      expect(grouped["real_estate_loan"].map { |bsl| bsl.liability.name }).to eq(["Prêt maison"])
      expect(grouped["short_term_debt"].map { |bsl| bsl.liability.name }).to eq(["Découvert"])
      expect(grouped["security_deposit"].map { |bsl| bsl.liability.name }).to eq(["Caution"])
    end
  end

  describe "#equity" do
    it "returns total_assets minus total_liabilities when everything is fully owned" do
      bs = create(:balance_sheet)
      user = bs.user
      asset = create(:asset, user: user, ownership_share: 100)
      liability = create(:liability, user: user, ownership_share: 100)
      create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 100_000)
      create(:balance_sheet_liability, balance_sheet: bs, liability: liability, remaining_capital: 60_000)

      expect(bs.equity).to eq(40_000)
    end

    it "reflects the share-adjusted totals" do
      bs = create(:balance_sheet)
      user = bs.user
      asset = create(:asset, user: user, ownership_share: 50)
      liability = create(:liability, user: user, ownership_share: 50)
      create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 100_000)
      create(:balance_sheet_liability, balance_sheet: bs, liability: liability, remaining_capital: 60_000)

      expect(bs.total_assets).to eq(50_000)
      expect(bs.total_liabilities).to eq(30_000)
      expect(bs.equity).to eq(20_000)
    end

    it "is zero on a balance sheet without any line" do
      bs = create(:balance_sheet)

      expect(bs.total_assets).to eq(0)
      expect(bs.total_liabilities).to eq(0)
      expect(bs.equity).to eq(0)
    end
  end
end
