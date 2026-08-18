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

  describe "#property_positions" do
    it "groups the lines of a property and derives its net value and LTV" do
      bs = create(:balance_sheet)
      user = bs.user
      property = create(:property, user: user, name: "Maison", usage: :primary_residence)
      asset = create(:asset, user: user, property: property, asset_type: :real_estate)
      loan = create(:liability, user: user, property: property, liability_type: :real_estate_loan)
      create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 400_000)
      create(:balance_sheet_liability, balance_sheet: bs, liability: loan, remaining_capital: 300_000)

      position = bs.property_positions.sole

      expect(position.property).to eq(property)
      expect(position).not_to be_unassigned
      expect(position.gross).to eq(400_000)
      expect(position.debt).to eq(300_000)
      expect(position.net).to eq(100_000)
      expect(position.ltv).to eq(75.0)
    end

    it "counts only the owned share of each line" do
      bs = create(:balance_sheet)
      user = bs.user
      property = create(:property, user: user)
      asset = create(:asset, user: user, property: property, asset_type: :real_estate, ownership_share: 50)
      loan = create(:liability, user: user, property: property, liability_type: :real_estate_loan, ownership_share: 50)
      create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 400_000)
      create(:balance_sheet_liability, balance_sheet: bs, liability: loan, remaining_capital: 300_000)

      position = bs.property_positions.sole

      expect(position.gross).to eq(200_000)
      expect(position.debt).to eq(150_000)
      expect(position.net).to eq(50_000)
      expect(position.ltv).to eq(75.0)
    end

    it "orders the positions by usage then name" do
      bs = create(:balance_sheet)
      user = bs.user
      properties = [
        create(:property, user: user, name: "Studio", usage: :rental),
        create(:property, user: user, name: "Chalet", usage: :secondary_residence),
        create(:property, user: user, name: "Appartement", usage: :rental),
        create(:property, user: user, name: "Maison", usage: :primary_residence)
      ]
      properties.each do |property|
        asset = create(:asset, user: user, property: property, asset_type: :real_estate)
        create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 100_000)
      end

      expect(bs.property_positions.map { |position| position.property.name })
        .to eq(["Maison", "Appartement", "Studio", "Chalet"])
    end

    it "leaves out properties without any line on this balance sheet" do
      bs = create(:balance_sheet)
      user = bs.user
      elsewhere = create(:property, user: user, name: "Ailleurs")
      asset = create(:asset, user: user, property: elsewhere, asset_type: :real_estate)
      other_bs = create(:balance_sheet, user: user, closing_date: bs.closing_date - 1.year)
      create(:balance_sheet_asset, balance_sheet: other_bs, asset: asset, value: 100_000)

      expect(bs.property_positions).to be_empty
    end

    it "collects the unlinked real estate lines in a last unassigned position" do
      bs = create(:balance_sheet)
      user = bs.user
      property = create(:property, user: user, name: "Maison")
      linked = create(:asset, user: user, property: property, asset_type: :real_estate)
      orphan = create(:asset, user: user, name: "Terrain", asset_type: :real_estate)
      orphan_loan = create(:liability, user: user, name: "Prêt terrain", liability_type: :real_estate_loan)
      orphan_deposit = create(:liability, user: user, name: "Caution", liability_type: :security_deposit)
      create(:balance_sheet_asset, balance_sheet: bs, asset: linked, value: 400_000)
      create(:balance_sheet_asset, balance_sheet: bs, asset: orphan, value: 80_000)
      create(:balance_sheet_liability, balance_sheet: bs, liability: orphan_loan, remaining_capital: 20_000)
      create(:balance_sheet_liability, balance_sheet: bs, liability: orphan_deposit, remaining_capital: 1_000)

      unassigned = bs.property_positions.last

      expect(bs.property_positions.size).to eq(2)
      expect(unassigned).to be_unassigned
      expect(unassigned.property).to be_nil
      expect(unassigned.asset_lines.map { |line| line.asset.name }).to eq(["Terrain"])
      expect(unassigned.liability_lines.map { |line| line.liability.name }).to eq(["Caution", "Prêt terrain"])
      expect(unassigned.gross).to eq(80_000)
      expect(unassigned.debt).to eq(21_000)
      expect(unassigned.net).to eq(59_000)
    end

    it "ignores unlinked lines that are not about real estate" do
      bs = create(:balance_sheet)
      user = bs.user
      cash = create(:asset, user: user, asset_type: :cash)
      overdraft = create(:liability, user: user, liability_type: :short_term_debt)
      create(:balance_sheet_asset, balance_sheet: bs, asset: cash, value: 5_000)
      create(:balance_sheet_liability, balance_sheet: bs, liability: overdraft, remaining_capital: 1_200)

      expect(bs.property_positions).to be_empty
    end

    it "keeps a property line even when it is not a real estate asset" do
      bs = create(:balance_sheet)
      user = bs.user
      property = create(:property, user: user)
      charges = create(:asset, user: user, property: property, asset_type: :checking_account)
      works = create(:liability, user: user, property: property, liability_type: :short_term_debt)
      create(:balance_sheet_asset, balance_sheet: bs, asset: charges, value: 3_000)
      create(:balance_sheet_liability, balance_sheet: bs, liability: works, remaining_capital: 1_000)

      position = bs.property_positions.sole

      expect(position.gross).to eq(3_000)
      expect(position.debt).to eq(1_000)
    end

    it "returns no LTV when the position has no gross value" do
      bs = create(:balance_sheet)
      user = bs.user
      property = create(:property, user: user)
      loan = create(:liability, user: user, property: property, liability_type: :real_estate_loan)
      create(:balance_sheet_liability, balance_sheet: bs, liability: loan, remaining_capital: 300_000)

      position = bs.property_positions.sole

      expect(position.gross).to eq(0)
      expect(position.ltv).to be_nil
      expect(position.net).to eq(-300_000)
    end
  end

  describe "#real_estate_totals_by_usage" do
    def build_property(bs, name:, usage:, value:, debt: 0)
      user = bs.user
      property = create(:property, user: user, name: name, usage: usage)
      asset = create(:asset, user: user, property: property, asset_type: :real_estate)
      create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: value)
      return property if debt.zero?

      loan = create(:liability, user: user, property: property, liability_type: :real_estate_loan)
      create(:balance_sheet_liability, balance_sheet: bs, liability: loan, remaining_capital: debt)
      property
    end

    it "sums the positions of each usage and closes with the overall total" do
      bs = create(:balance_sheet)
      build_property(bs, name: "Maison", usage: :primary_residence, value: 400_000, debt: 300_000)
      build_property(bs, name: "Studio", usage: :rental, value: 100_000, debt: 60_000)
      build_property(bs, name: "Appartement", usage: :rental, value: 200_000, debt: 20_000)

      totals = bs.real_estate_totals_by_usage

      expect(totals.keys).to eq(["primary_residence", "rental", :total])
      expect(totals["primary_residence"]).to have_attributes(gross: 400_000, debt: 300_000, net: 100_000, ltv: 75.0)
      expect(totals["rental"]).to have_attributes(gross: 300_000, debt: 80_000, net: 220_000)
      expect(totals[:total]).to have_attributes(gross: 700_000, debt: 380_000, net: 320_000, ltv: 54.3)
    end

    it "derives the overall LTV from the combined gross and debt" do
      bs = create(:balance_sheet)
      build_property(bs, name: "Maison", usage: :primary_residence, value: 400_000, debt: 300_000)

      expect(bs.real_estate_totals_by_usage[:total].ltv).to eq(75.0)
    end

    it "keys the unassigned bucket with nil and keeps it after the usages" do
      bs = create(:balance_sheet)
      user = bs.user
      build_property(bs, name: "Maison", usage: :primary_residence, value: 400_000)
      orphan = create(:asset, user: user, name: "Terrain", asset_type: :real_estate)
      create(:balance_sheet_asset, balance_sheet: bs, asset: orphan, value: 80_000)

      totals = bs.real_estate_totals_by_usage

      expect(totals.keys).to eq(["primary_residence", nil, :total])
      expect(totals[nil]).to have_attributes(gross: 80_000, debt: 0, net: 80_000, ltv: 0.0)
      expect(totals[:total].gross).to eq(480_000)
    end

    it "only holds the total on a balance sheet without any property line" do
      bs = create(:balance_sheet)

      totals = bs.real_estate_totals_by_usage

      expect(totals.keys).to eq([:total])
      expect(totals[:total]).to have_attributes(gross: 0, debt: 0, net: 0, ltv: nil)
    end
  end

  describe "#previous" do
    it "returns the closest earlier balance sheet of the user" do
      user = create(:user)
      create(:balance_sheet, user: user, closing_date: Date.new(2023, 12, 31))
      last_year = create(:balance_sheet, user: user, closing_date: Date.new(2024, 12, 31))
      bs = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))

      expect(bs.previous).to eq(last_year)
    end

    it "returns nil on the user's very first balance sheet" do
      user = create(:user)
      bs = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
      create(:balance_sheet, user: user, closing_date: Date.new(2026, 12, 31))

      expect(bs.previous).to be_nil
    end

    it "ignores the balance sheets of another user" do
      bs = create(:balance_sheet, closing_date: Date.new(2025, 12, 31))
      create(:balance_sheet, closing_date: Date.new(2024, 12, 31))

      expect(bs.previous).to be_nil
    end
  end

  describe ".variation_between" do
    it "carries the gain and the rate it represents" do
      variation = BalanceSheet.variation_between(200_000, 250_000)

      expect(variation).to have_attributes(amount: 50_000, rate: 25.0)
      expect(variation.gain?).to be(true)
    end

    it "carries a loss as a negative amount and a negative rate" do
      variation = BalanceSheet.variation_between(200_000, 150_000)

      expect(variation).to have_attributes(amount: -50_000, rate: -25.0)
      expect(variation.loss?).to be(true)
    end

    it "has no rate to give when the previous amount was zero" do
      variation = BalanceSheet.variation_between(0, 50_000)

      expect(variation).to have_attributes(amount: 50_000, rate: nil)
    end

    it "reads the rate against the magnitude of a negative starting point" do
      variation = BalanceSheet.variation_between(-10_000, -5_000)

      expect(variation).to have_attributes(amount: 5_000, rate: 50.0)
    end

    it "reports an unchanged amount as flat" do
      variation = BalanceSheet.variation_between(200_000, 200_000)

      expect(variation.flat?).to be(true)
      expect(variation.rate).to eq(0)
    end
  end

  describe "#variations_against" do
    it "reads the three totals of the synthèse against the previous balance sheet" do
      user = create(:user)
      previous = create(:balance_sheet, user: user, closing_date: Date.new(2024, 12, 31))
      bs = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
      asset = create(:asset, user: user)
      loan = create(:liability, user: user)
      create(:balance_sheet_asset, balance_sheet: previous, asset: asset, value: 100_000)
      create(:balance_sheet_liability, balance_sheet: previous, liability: loan, remaining_capital: 60_000)
      create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 120_000)
      create(:balance_sheet_liability, balance_sheet: bs, liability: loan, remaining_capital: 50_000)

      variations = bs.variations_against(previous)

      expect(variations[:assets]).to have_attributes(amount: 20_000, rate: 20.0)
      expect(variations[:liabilities]).to have_attributes(amount: -10_000, rate: -16.7)
      expect(variations[:equity]).to have_attributes(amount: 30_000, rate: 75.0)
    end
  end

  describe "#real_estate_variation_against" do
    def build_property(bs, name:, usage:, value:, debt: 0, property: nil)
      user = bs.user
      property ||= create(:property, user: user, name: name, usage: usage)
      asset = create(:asset, user: user, property: property, asset_type: :real_estate)
      create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: value)
      return property if debt.zero?

      loan = create(:liability, user: user, property: property, liability_type: :real_estate_loan)
      create(:balance_sheet_liability, balance_sheet: bs, liability: loan, remaining_capital: debt)
      property
    end

    it "reads the overall valeur nette against the previous balance sheet" do
      user = create(:user)
      previous = create(:balance_sheet, user: user, closing_date: Date.new(2024, 12, 31))
      bs = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
      home = build_property(previous, name: "Maison", usage: :primary_residence, value: 400_000, debt: 300_000)
      build_property(bs, name: "Maison", usage: :primary_residence, value: 420_000, debt: 280_000, property: home)

      expect(bs.real_estate_variation_against(previous)).to have_attributes(amount: 40_000, rate: 40.0)
    end

    it "counts a patrimoine immobilier built since the previous sheet as a full gain, with no rate" do
      user = create(:user)
      previous = create(:balance_sheet, user: user, closing_date: Date.new(2024, 12, 31))
      bs = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
      build_property(bs, name: "Studio", usage: :rental, value: 100_000, debt: 80_000)

      expect(bs.real_estate_variation_against(previous)).to have_attributes(amount: 20_000, rate: nil)
    end

    it "leaves the unassigned lines out of both sides, as the tab leaves them out of the rows" do
      user = create(:user)
      previous = create(:balance_sheet, user: user, closing_date: Date.new(2024, 12, 31))
      bs = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
      home = build_property(previous, name: "Maison", usage: :primary_residence, value: 400_000)
      build_property(bs, name: "Maison", usage: :primary_residence, value: 450_000, property: home)
      orphan = create(:asset, user: user, name: "Terrain", asset_type: :real_estate)
      create(:balance_sheet_asset, balance_sheet: previous, asset: orphan, value: 30_000)
      create(:balance_sheet_asset, balance_sheet: bs, asset: orphan, value: 80_000)

      expect(bs.real_estate_variation_against(previous)).to have_attributes(amount: 50_000, rate: 12.5)
    end
  end

  describe ".timeline_for" do
    let(:user) { create(:user) }

    it "gives each balance sheet the very totals it reports itself" do
      first = create(:balance_sheet, user: user, closing_date: Date.new(2025, 6, 30))
      second = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
      create(:balance_sheet_asset, balance_sheet: first, asset: create(:asset, user: user), value: 100_000)
      create(:balance_sheet_asset, balance_sheet: second, asset: create(:asset, user: user, ownership_share: 50), value: 200_000)
      create(:balance_sheet_liability, balance_sheet: second, liability: create(:liability, user: user), remaining_capital: 40_000)

      timeline = BalanceSheet.timeline_for([first, second])

      expect(timeline.map(&:total_assets)).to eq([first.total_assets, second.total_assets])
      expect(timeline.map(&:total_liabilities)).to eq([first.total_liabilities, second.total_liabilities])
      expect(timeline.map(&:equity)).to eq([first.equity, second.equity])
      expect(timeline.map(&:closing_date)).to eq([first.closing_date, second.closing_date])
    end

    # Un bilan sans ligne n'a pas de groupe dans le GROUP BY : il doit retomber sur zéro,
    # pas disparaître de la série ni faire échouer la lecture.
    it "reports zero for a balance sheet holding no line" do
      empty = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))

      point = BalanceSheet.timeline_for([empty]).first

      expect(point.total_assets).to eq(0)
      expect(point.total_liabilities).to eq(0)
      expect(point.equity).to eq(0)
    end

    it "returns nothing for an empty set, without querying" do
      expect(BalanceSheet.timeline_for([])).to eq([])
    end

    # La raison d'être de la méthode : deux requêtes agrégées pour toute la série, et non
    # deux par bilan. Sans cette garantie le tableau de bord ferait grossir sa charge à
    # chaque nouvelle clôture.
    it "reads the whole series in two aggregate queries" do
      sheets = 3.times.map do |index|
        sheet = create(:balance_sheet, user: user, closing_date: Date.new(2025, 1, 1) + index.months)
        create(:balance_sheet_asset, balance_sheet: sheet, asset: create(:asset, user: user), value: 1_000)
        sheet
      end

      queries = 0
      subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
        queries += 1 unless payload[:name].in?(["SCHEMA", "TRANSACTION"]) || payload[:sql].start_with?("BEGIN", "COMMIT")
      end
      BalanceSheet.timeline_for(sheets)
      ActiveSupport::Notifications.unsubscribe(subscription)

      expect(queries).to eq(2)
    end
  end


  describe ".assets_breakdown_for" do
    let(:user) { create(:user) }

    it "gives one series per type, in the enum order, with a value per balance sheet" do
      livret = create(:asset, user: user, asset_type: :savings_account)
      cash = create(:asset, user: user, asset_type: :cash)
      first = create(:balance_sheet, user: user, closing_date: Date.new(2025, 6, 30))
      second = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
      create(:balance_sheet_asset, balance_sheet: first, asset: livret, value: 10_000)
      create(:balance_sheet_asset, balance_sheet: first, asset: cash, value: 500)
      create(:balance_sheet_asset, balance_sheet: second, asset: livret, value: 12_000)

      series = BalanceSheet.assets_breakdown_for([first, second])

      expect(series.map(&:key)).to eq(%w[cash savings_account])
      expect(series.map(&:values)).to eq([[500, 0], [10_000, 12_000]])
    end

    # L'éclatement par usage est la raison d'être de la méthode : un patrimoine immobilier
    # lu d'un seul tenant ne dit pas lequel des biens a bougé.
    it "splits the immobilier by usage of the bien, unassigned last" do
      sheet = create(:balance_sheet, user: user)
      rental = create(:property, user: user, name: "Locatif", usage: :rental)
      home = create(:property, user: user, name: "Maison", usage: :primary_residence)
      orphan = create(:asset, user: user, name: "Terrain", asset_type: :real_estate)
      create(:balance_sheet_asset, balance_sheet: sheet, asset: rental.real_estate_asset, value: 200_000)
      create(:balance_sheet_asset, balance_sheet: sheet, asset: home.real_estate_asset, value: 300_000)
      create(:balance_sheet_asset, balance_sheet: sheet, asset: orphan, value: 40_000)

      series = BalanceSheet.assets_breakdown_for([sheet])

      expect(series.map(&:key)).to eq(%w[
        real_estate:primary_residence real_estate:rental real_estate:unassigned
      ])
      expect(series.map(&:values).flatten).to eq([300_000, 200_000, 40_000])
      expect(series.first.label).to eq("Immobilier · Résidence principale")
    end

    # Seul l'immobilier est éclaté : regrouper toutes les lignes d'un bien est le travail de
    # l'onglet Immobilier, pas celui d'une ventilation par catégorie.
    it "leaves a non-immobilier line attached to a bien under its own type" do
      sheet = create(:balance_sheet, user: user)
      property = create(:property, user: user, name: "Maison", usage: :primary_residence)
      account = create(:asset, user: user, asset_type: :checking_account, property: property)
      create(:balance_sheet_asset, balance_sheet: sheet, asset: account, value: 5_000)

      series = BalanceSheet.assets_breakdown_for([sheet])

      expect(series.map(&:key)).to include("checking_account")
      expect(series.map(&:key)).not_to include("checking_account:primary_residence")
    end

    it "sums two biens of the same usage into a single series" do
      sheet = create(:balance_sheet, user: user)
      %w[Lyon Paris].each do |name|
        property = create(:property, user: user, name: name, usage: :rental)
        create(:balance_sheet_asset, balance_sheet: sheet, asset: property.real_estate_asset, value: 100_000)
      end

      series = BalanceSheet.assets_breakdown_for([sheet])

      expect(series.map(&:key)).to eq(["real_estate:rental"])
      expect(series.first.values).to eq([200_000])
    end

    it "counts only the owned share of a line" do
      sheet = create(:balance_sheet, user: user)
      asset = create(:asset, user: user, asset_type: :savings_account, ownership_share: 50)
      create(:balance_sheet_asset, balance_sheet: sheet, asset: asset, value: 20_000)

      expect(BalanceSheet.assets_breakdown_for([sheet]).first.values).to eq([10_000])
    end

    # La somme des bandes est le haut de la pile : elle doit tomber sur le total du bilan,
    # sinon la courbe des fonds propres et l'aire empilée ne raconteraient pas la même chose.
    it "adds up to the total the balance sheet reports" do
      sheet = create(:balance_sheet, user: user)
      property = create(:property, user: user, name: "Maison", usage: :primary_residence)
      create(:balance_sheet_asset, balance_sheet: sheet, asset: property.real_estate_asset, value: 300_000)
      create(:balance_sheet_asset, balance_sheet: sheet,
                                   asset: create(:asset, user: user, ownership_share: 30),
                                   value: 12_345.67)

      series = BalanceSheet.assets_breakdown_for([sheet])

      expect(series.sum { |serie| serie.values.first }).to eq(sheet.total_assets)
    end

    it "returns nothing for an empty set" do
      expect(BalanceSheet.assets_breakdown_for([])).to eq([])
    end
  end

  describe ".liabilities_breakdown_for" do
    let(:user) { create(:user) }

    it "splits the crédits immobiliers by usage and leaves the other types whole" do
      sheet = create(:balance_sheet, user: user)
      property = create(:property, user: user, name: "Locatif", usage: :rental)
      loan = create(:liability, user: user, liability_type: :real_estate_loan, property: property)
      deposit = create(:liability, user: user, liability_type: :security_deposit)
      create(:balance_sheet_liability, balance_sheet: sheet, liability: loan, remaining_capital: 150_000)
      create(:balance_sheet_liability, balance_sheet: sheet, liability: deposit, remaining_capital: 1_200)

      series = BalanceSheet.liabilities_breakdown_for([sheet])

      expect(series.map(&:key)).to eq(%w[real_estate_loan:rental security_deposit])
      expect(series.first.label).to eq("Crédit immobilier · Locatif")
    end

    it "adds up to the total the balance sheet reports" do
      sheet = create(:balance_sheet, user: user)
      loan = create(:liability, user: user, liability_type: :real_estate_loan, ownership_share: 50)
      create(:balance_sheet_liability, balance_sheet: sheet, liability: loan, remaining_capital: 99_999.99)

      series = BalanceSheet.liabilities_breakdown_for([sheet])

      expect(series.sum { |serie| serie.values.first }).to eq(sheet.total_liabilities)
    end
  end

end
