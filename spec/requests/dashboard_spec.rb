require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def currency(amount)
    ActionController::Base.helpers.number_to_currency(amount)
  end

  # Un bilan doté d'un actif et d'une dette, pour que ses totaux ne soient pas nuls.
  def balance_sheet_worth(closing_date, value:, debt: 0)
    sheet = create(:balance_sheet, user: user, closing_date: closing_date)
    create(:balance_sheet_asset, balance_sheet: sheet, asset: create(:asset, user: user), value: value)
    create(:balance_sheet_liability, balance_sheet: sheet, liability: create(:liability, user: user), remaining_capital: debt) if debt.positive?
    sheet
  end

  describe "GET /" do
    it "is the dashboard for a signed-in user" do
      get root_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("views.dashboard.title"))
    end

    it "invites the user to create a first balance sheet when there is none" do
      get root_path

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css(".empty-state").text).to include(I18n.t("views.dashboard.empty"))
      expect(doc.at_css(".chart-line")).to be_nil
      expect(doc.at_css(".stat-grid")).to be_nil
    end

    it "headlines the net worth of the most recent balance sheet" do
      balance_sheet_worth(Date.new(2025, 6, 30), value: 100_000, debt: 40_000)
      balance_sheet_worth(Date.new(2025, 12, 31), value: 120_000, debt: 30_000)

      get root_path

      doc = Nokogiri::HTML(response.body)
      headline = doc.at_css(".stat-card-highlight")
      expect(headline.at_css(".stat-value").text.strip).to eq(currency(90_000))
      expect(headline.at_css(".stat-hint").text).to include("31 décembre 2025")
    end

    it "reads the variation against the previous balance sheet" do
      balance_sheet_worth(Date.new(2025, 6, 30), value: 100_000)
      balance_sheet_worth(Date.new(2025, 12, 31), value: 120_000)

      get root_path

      doc = Nokogiri::HTML(response.body)
      variation = doc.css(".stat-card .variation").first
      expect(variation.text).to include("+#{currency(20_000)}")
      expect(variation["class"]).to include("variation-gain")
    end

    it "plots one point per balance sheet, oldest first" do
      balance_sheet_worth(Date.new(2024, 12, 31), value: 100_000)
      balance_sheet_worth(Date.new(2025, 6, 30), value: 110_000)
      balance_sheet_worth(Date.new(2025, 12, 31), value: 120_000)

      get root_path

      doc = Nokogiri::HTML(response.body)
      points = doc.css(".chart-line .chart-point title").map(&:text)
      expect(points.size).to eq(3)
      expect(points.first).to include("31 décembre 2024").and include(currency(100_000))
      expect(points.last).to include("31 décembre 2025").and include(currency(120_000))
    end

    # La variation annuelle se lit sur le bilan le plus récent qui ait un an de recul : lire
    # trois mois d'historique et l'annoncer comme une progression sur un an serait faux.
    describe "the over-a-year variation" do
      it "reads against the most recent balance sheet at least a year older" do
        balance_sheet_worth(Date.new(2024, 12, 31), value: 100_000)
        balance_sheet_worth(Date.new(2025, 6, 30), value: 110_000)
        balance_sheet_worth(Date.new(2025, 12, 31), value: 130_000)

        get root_path

        card = Nokogiri::HTML(response.body).css(".stat-card").find { |c|
          c.at_css(".stat-label").text.strip == I18n.t("views.dashboard.over_a_year")
        }
        expect(card.at_css(".variation").text).to include("+#{currency(30_000)}")
        expect(card.at_css(".stat-hint").text).to include("31 décembre 2024")
      end

      it "stays blank while the history is shorter than a year" do
        balance_sheet_worth(Date.new(2025, 6, 30), value: 100_000)
        balance_sheet_worth(Date.new(2025, 12, 31), value: 120_000)

        get root_path

        card = Nokogiri::HTML(response.body).css(".stat-card").find { |c|
          c.at_css(".stat-label").text.strip == I18n.t("views.dashboard.over_a_year")
        }
        expect(card.at_css(".variation")).to be_nil
        expect(card.at_css(".stat-value").text.strip).to eq("—")
        expect(card.at_css(".stat-hint").text.strip).to eq(I18n.t("views.dashboard.no_year_ago"))
      end
    end

    describe "the assets area chart" do
      it "stacks one band per category, in a stable order" do
        sheet = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
        create(:balance_sheet_asset, balance_sheet: sheet,
                                     asset: create(:asset, user: user, asset_type: :savings_account),
                                     value: 30_000)
        create(:balance_sheet_asset, balance_sheet: sheet,
                                     asset: create(:asset, user: user, asset_type: :financial_investment),
                                     value: 10_000)

        get root_path

        bands = Nokogiri::HTML(response.body).css(".chart-area-stack").first.css(".chart-series-area")
        expect(bands.map { |band| band["class"] }).to eq([
          "chart-series-area chart-series-savings-account",
          "chart-series-area chart-series-financial-investment"
        ])
      end

      # La demande derrière ces courbes : l'immobilier d'un seul tenant ne dit pas ce qui
      # bouge. Chaque usage porte sa propre bande, donc sa propre nuance.
      it "splits the immobilier by usage of the bien" do
        sheet = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
        %i[primary_residence rental secondary_residence].each_with_index do |usage, index|
          property = create(:property, user: user, name: "Bien #{index}", usage: usage)
          create(:balance_sheet_asset, balance_sheet: sheet,
                                       asset: property.real_estate_asset,
                                       value: 100_000 + index * 1_000)
        end

        get root_path

        bands = Nokogiri::HTML(response.body).css(".chart-area-stack").first.css(".chart-series-area")
        expect(bands.map { |band| band["class"].split.last }).to eq(%w[
          chart-series-real-estate-primary-residence
          chart-series-real-estate-rental
          chart-series-real-estate-secondary-residence
        ])
      end

      it "carries the immobilier lines without a bien in a band of their own" do
        sheet = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
        orphan = create(:asset, user: user, name: "Terrain", asset_type: :real_estate)
        create(:balance_sheet_asset, balance_sheet: sheet, asset: orphan, value: 40_000)

        get root_path

        doc = Nokogiri::HTML(response.body)
        expect(doc.at_css(".chart-series-real-estate-unassigned")).not_to be_nil
        expect(doc.css(".chart-legend-label").map(&:text)).to include("Immobilier · Non rattaché")
      end

      # Une catégorie qui n'existe que sur les bilans anciens garde sa bande : sans la valeur
      # zéro sur les bilans récents, la série se décalerait d'un cran sur l'axe.
      it "carries a zero for the balance sheets a category is absent from" do
        livret = create(:asset, user: user, asset_type: :savings_account)
        pea = create(:asset, user: user, asset_type: :financial_investment)
        first = create(:balance_sheet, user: user, closing_date: Date.new(2025, 6, 30))
        second = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
        create(:balance_sheet_asset, balance_sheet: first, asset: livret, value: 10_000)
        create(:balance_sheet_asset, balance_sheet: second, asset: livret, value: 12_000)
        create(:balance_sheet_asset, balance_sheet: second, asset: pea, value: 8_000)

        get root_path

        expect(BalanceSheet.assets_breakdown_for([first, second]).map(&:values))
          .to eq([[10_000, 12_000], [0, 8_000]])
        expect(response.body).to include("chart-series-financial-investment")
      end
    end

    describe "the dette area chart" do
      it "splits the crédits immobiliers by usage and keeps the other passifs whole" do
        property = create(:property, user: user, name: "Locatif Lyon", usage: :rental)
        loan = create(:liability, user: user, liability_type: :real_estate_loan, property: property)
        deposit = create(:liability, user: user, liability_type: :security_deposit)
        sheet = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
        create(:balance_sheet_liability, balance_sheet: sheet, liability: loan, remaining_capital: 150_000)
        create(:balance_sheet_liability, balance_sheet: sheet, liability: deposit, remaining_capital: 1_200)

        get root_path

        bands = Nokogiri::HTML(response.body).css(".chart-area-stack").last
                  .css(".chart-series-area").map { |band| band["class"].split.last }
        expect(bands).to eq(%w[chart-series-real-estate-loan-rental chart-series-security-deposit])
      end

      it "says so plainly when the history carries no dette at all" do
        balance_sheet_worth(Date.new(2025, 12, 31), value: 50_000)

        get root_path

        dette = Nokogiri::HTML(response.body).css(".chart-card").find { |card|
          card.at_css(".chart-title")&.text == I18n.t("views.dashboard.liabilities_breakdown")
        }
        expect(dette.at_css(".empty-state").text).to eq(I18n.t("views.dashboard.no_liabilities"))
        expect(dette.at_css(".chart-area-stack")).to be_nil
      end
    end

    # La quote-part est déjà appliquée par les totaux du bilan ; le tableau de bord les lit
    # par une autre requête (BalanceSheet.timeline_for) et doit tomber sur le même montant.
    it "counts an asset held in part for its owned share only" do
      sheet = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
      create(:balance_sheet_asset, balance_sheet: sheet,
                                   asset: create(:asset, user: user, ownership_share: 50),
                                   value: 200_000)

      get root_path

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css(".stat-card-highlight .stat-value").text.strip).to eq(currency(100_000))
    end
  end
end
