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

    it "breaks the last balance sheet down by asset type" do
      sheet = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
      create(:balance_sheet_asset, balance_sheet: sheet,
                                   asset: create(:asset, user: user, asset_type: :savings_account),
                                   value: 30_000)
      create(:balance_sheet_asset, balance_sheet: sheet,
                                   asset: create(:asset, user: user, asset_type: :financial_investment),
                                   value: 10_000)

      get root_path

      legend = Nokogiri::HTML(response.body).css(".chart-donut .chart-legend-item")
      expect(legend.map { |item| item.at_css(".chart-legend-label").text }).to eq(
        [Asset.asset_type_label_for("savings_account"), Asset.asset_type_label_for("financial_investment")]
      )
      expect(legend.first.at_css(".chart-legend-share").text).to include("75")
    end

    # Les parts de l'anneau sont des cercles en pointillés : sans le trait d'union dans les
    # noms d'attributs, le navigateur les ignore en silence et les trois parts se superposent
    # en un unique cercle fin. Rien dans le HTML ne le trahirait sans cette lecture.
    it "gives each slice of the ring its own arc" do
      sheet = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
      create(:balance_sheet_asset, balance_sheet: sheet,
                                   asset: create(:asset, user: user, asset_type: :savings_account),
                                   value: 30_000)
      create(:balance_sheet_asset, balance_sheet: sheet,
                                   asset: create(:asset, user: user, asset_type: :financial_investment),
                                   value: 10_000)

      get root_path

      slices = Nokogiri::HTML(response.body).css(".chart-donut-ring .chart-slice")
      expect(slices.size).to eq(2)
      expect(slices.map { |slice| slice["stroke-width"] }).to all(be_present)
      # Trois quarts du tour pour la part de 75 %, et un décalage nul pour la première.
      expect(slices.first["stroke-dasharray"].split.first.to_f).to be_within(0.5).of(2 * Math::PI * 75 * 0.75)
      expect(slices.first["stroke-dashoffset"].to_f).to eq(0)
      expect(slices.last["stroke-dashoffset"].to_f).to be < 0
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
