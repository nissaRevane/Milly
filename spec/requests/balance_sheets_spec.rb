require "rails_helper"

RSpec.describe "BalanceSheets", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def currency(amount, **options)
    ActionController::Base.helpers.number_to_currency(amount, **options)
  end

  # Les variations sont arrondies à l'euro (voir ApplicationHelper#variation_label).
  def variation_currency(amount)
    currency(amount, precision: 0)
  end

  describe "GET /balance_sheets" do
    it "returns success" do
      get balance_sheets_path
      expect(response).to have_http_status(:success)
    end

    it "groups balance sheets by year in an accordion" do
      create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
      create(:balance_sheet, user: user, closing_date: Date.new(2025, 6, 30))
      create(:balance_sheet, user: user, closing_date: Date.new(2024, 12, 31))

      get balance_sheets_path

      doc = Nokogiri::HTML(response.body)
      items = doc.css(".balance-sheets-accordion .accordion-item")

      expect(items.map { |item| item.at_css(".accordion-year")&.text&.strip }).to eq(["2025", "2024"])
      expect(items.first["open"]).not_to be_nil
      expect(items.drop(1).map { |item| item["open"] }).to all(be_nil)
      expect(items.first.at_css(".badge")&.text&.strip).to eq("2")
    end

    it "links the row cells to the summary page instead of a dedicated button" do
      bs = create(:balance_sheet, user: user)

      get balance_sheets_path

      doc = Nokogiri::HTML(response.body)
      row = doc.at_css(".table tbody tr")

      row_links = row.css("a.row-link")
      expect(row_links).not_to be_empty
      expect(row_links.map { |link| link["href"] }).to all(eq(summary_balance_sheet_path(bs)))
      expect(doc.at_css(".table-actions a.btn-primary")).to be_nil
    end
  end

  describe "GET /balance_sheets/:id" do
    it "returns success" do
      bs = create(:balance_sheet, user: user)
      get balance_sheet_path(bs)
      expect(response).to have_http_status(:success)
    end

    describe "stepping between bilans" do
      it "links each arrow to the neighbouring bilan" do
        older = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
        current = create(:balance_sheet, user: user, closing_date: Date.new(2026, 6, 30))
        newer = create(:balance_sheet, user: user, closing_date: Date.new(2026, 12, 31))

        get balance_sheet_path(current)

        doc = Nokogiri::HTML(response.body)
        expect(doc.at_css(".summary-nav a[rel=prev]")["href"]).to eq(balance_sheet_path(older))
        expect(doc.at_css(".summary-nav a[rel=next]")["href"]).to eq(balance_sheet_path(newer))
      end

      it "disables the arrow that has no bilan on its side" do
        only = create(:balance_sheet, user: user, closing_date: Date.new(2026, 6, 30))

        get balance_sheet_path(only)

        doc = Nokogiri::HTML(response.body)
        expect(doc.css(".summary-nav a")).to be_empty
        expect(doc.css(".summary-nav .summary-nav-arrow-disabled").size).to eq(2)
      end

      it "ignores the bilans of another user" do
        current = create(:balance_sheet, user: user, closing_date: Date.new(2026, 6, 30))
        other = create(:user)
        create(:balance_sheet, user: other, closing_date: Date.new(2026, 12, 31))

        get balance_sheet_path(current)

        expect(Nokogiri::HTML(response.body).css(".summary-nav a")).to be_empty
      end
    end

    it "renders the owned amount, the share and the full amount in a single cell" do
      bs = create(:balance_sheet, user: user)
      half = create(:asset, user: user, name: "Maison", asset_type: :real_estate, ownership_share: 50)
      quarter = create(:asset, user: user, name: "Terrain", asset_type: :real_estate, ownership_share: 25)
      create(:balance_sheet_asset, balance_sheet: bs, asset: half, value: 200_000)
      create(:balance_sheet_asset, balance_sheet: bs, asset: quarter, value: 80_000)

      get balance_sheet_path(bs)

      expect(response).to have_http_status(:success)
      doc = Nokogiri::HTML(response.body)
      cells = doc.css(".balance-sheet-columns table.table tbody tr:not(.table-group-header)").map { |row| row.at_css("td.text-right").text.gsub(/\s+/, " ").strip }

      expect(cells).to contain_exactly(
        "#{currency(100_000)}50 % de #{currency(200_000)}".gsub(/\s+/, " "),
        "#{currency(20_000)}25 % de #{currency(80_000)}".gsub(/\s+/, " ")
      )
      expect(bs.total_assets).to eq(120_000)
      expect(response.body).to include(currency(120_000))
    end

    it "renders only the value for a fully owned line" do
      bs = create(:balance_sheet, user: user)
      asset = create(:asset, user: user, name: "Livret A", ownership_share: 100)
      create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 5_000)

      get balance_sheet_path(bs)

      doc = Nokogiri::HTML(response.body)
      cell = doc.at_css(".balance-sheet-columns table.table tbody tr:not(.table-group-header) td.text-right")

      expect(cell.text.gsub(/\s+/, " ").strip).to eq(currency(5_000).gsub(/\s+/, " "))
      expect(cell.at_css(".owned-value-detail")).to be_nil
    end

    it "groups the lines by type under a single header row per type" do
      bs = create(:balance_sheet, user: user)
      livret = create(:asset, user: user, name: "Livret A", asset_type: :cash)
      compte = create(:asset, user: user, name: "Compte courant", asset_type: :cash)
      immo = create(:asset, user: user, name: "Maison", asset_type: :real_estate)
      loan = create(:liability, user: user, name: "Prêt", liability_type: :real_estate_loan)
      create(:balance_sheet_asset, balance_sheet: bs, asset: livret, value: 1_000)
      create(:balance_sheet_asset, balance_sheet: bs, asset: compte, value: 500)
      create(:balance_sheet_asset, balance_sheet: bs, asset: immo, value: 200_000)
      create(:balance_sheet_liability, balance_sheet: bs, liability: loan, remaining_capital: 150_000)

      get balance_sheet_path(bs)

      expect(response).to have_http_status(:success)
      doc = Nokogiri::HTML(response.body)
      headers = doc.css(".balance-sheet-columns .table-group-header")

      expect(headers.map { |row| row.at_css(".badge").text.strip }).to eq(["Cash", "Immobilier", "Crédit immobilier"])
      expect(headers.map { |row| row.at_css(".summary-category-count").text.strip }).to eq(["2", "1", "1"])
      cash_header = headers.first
      expect(cash_header.at_css(".table-group-amount").text.gsub(/\s+/, " ").strip).to eq(currency(1_500).gsub(/\s+/, " "))
    end

    # Le type est déjà écrit sur l'en-tête du groupe : la ligne n'a plus qu'un nom, et c'est
    # la couleur de sa pastille qui porte le risque. Le libellé reste en infobulle, une
    # couleur seule ne disant rien à qui ne la voit pas.
    it "colors each line by its risk level and names it in the tooltip" do
      bs = create(:balance_sheet, user: user)
      asset = create(:asset, user: user, name: "Livret A", asset_type: :cash, risk_level: :low)
      create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 1_000)

      get balance_sheet_path(bs)

      doc = Nokogiri::HTML(response.body)
      row = doc.at_css(".balance-sheet-columns table.table tbody tr:not(.table-group-header)")
      badge = row.at_css(".badge.badge-success")

      expect(badge.text.strip).to eq("Livret A")
      expect(badge["title"]).to eq("Faible")
    end

    it "replaces the edit link with an inline value form on each line" do
      bs = create(:balance_sheet, user: user)
      asset = create(:asset, user: user, name: "Livret A", asset_type: :cash)
      loan = create(:liability, user: user, name: "Prêt", liability_type: :real_estate_loan)
      bsa = create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 1_000)
      bsl = create(:balance_sheet_liability, balance_sheet: bs, liability: loan, remaining_capital: 150_000)

      get balance_sheet_path(bs)

      doc = Nokogiri::HTML(response.body)
      expect(doc.css("a[href='#{edit_balance_sheet_balance_sheet_asset_path(bs, bsa)}']")).to be_empty
      expect(doc.css("a[href='#{edit_balance_sheet_balance_sheet_liability_path(bs, bsl)}']")).to be_empty

      asset_form = doc.at_css("form[action='#{balance_sheet_balance_sheet_asset_path(bs, bsa)}'].inline-edit-form")
      expect(asset_form).not_to be_nil
      expect(asset_form["hidden"]).not_to be_nil
      expect(asset_form.at_css("input[name='balance_sheet_asset[value]']")["value"]).to eq("1000")

      liability_form = doc.at_css("form[action='#{balance_sheet_balance_sheet_liability_path(bs, bsl)}'].inline-edit-form")
      expect(liability_form).not_to be_nil
      expect(liability_form["hidden"]).not_to be_nil
      expect(liability_form.at_css("input[name='balance_sheet_liability[remaining_capital]']")["value"]).to eq("150000")
    end

    it "edits the closing date from the title instead of a separate edit page" do
      bs = create(:balance_sheet, user: user, closing_date: Date.new(2026, 6, 30))

      get balance_sheet_path(bs)

      doc = Nokogiri::HTML(response.body)
      expect(doc.css("a[href='#{edit_balance_sheet_path(bs)}']")).to be_empty

      form = doc.at_css(".page-header form[action='#{balance_sheet_path(bs)}'].inline-edit-form")
      expect(form).not_to be_nil
      expect(form["hidden"]).not_to be_nil
      expect(form.at_css("input[name='_method']")["value"]).to eq("patch")

      field = form.at_css("input[name='balance_sheet[closing_date]']")
      expect(field["type"]).to eq("date")
      expect(field["value"]).to eq("2026-06-30")
    end
  end

  describe "the real estate band" do
    # A bien with a 200k flat financed by a 150k loan, plus an unlinked real estate asset.
    def previous_label
      I18n.t("views.balance_sheets.summary.charts.since_previous")
    end

    def yearly_label
      I18n.t("views.balance_sheets.summary.charts.over_a_year")
    end

    def create_sheet_worth(closing_date, value:, debt: 0)
      sheet = create(:balance_sheet, user: user, closing_date: closing_date)
      create(:balance_sheet_asset, balance_sheet: sheet, asset: create(:asset, user: user), value: value)
      if debt.positive?
        create(:balance_sheet_liability, balance_sheet: sheet,
                                         liability: create(:liability, user: user), remaining_capital: debt)
      end
      sheet
    end

    def build_property_sheet(with_unassigned: false)
      bs = create(:balance_sheet, user: user)
      property = create(:property, user: user, name: "Appartement Lyon", usage: :rental)
      asset = create(:asset, user: user, name: "Appartement", asset_type: :real_estate, property: property)
      loan = create(:liability, user: user, name: "Prêt Lyon", liability_type: :real_estate_loan, property: property)
      create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 200_000)
      create(:balance_sheet_liability, balance_sheet: bs, liability: loan, remaining_capital: 150_000)

      if with_unassigned
        orphan = create(:asset, user: user, name: "Terrain orphelin", asset_type: :real_estate)
        create(:balance_sheet_asset, balance_sheet: bs, asset: orphan, value: 40_000)
      end

      bs
    end

    describe "on the show page" do
      # The bilan lists the lines once, in its actifs and passifs columns. Regrouping them
      # per bien belongs to the synthèse, which is where that reading lives now.
      it "does not repeat the lines regrouped per bien" do
        bs = build_property_sheet(with_unassigned: true)

        get balance_sheet_path(bs)

        expect(response).to have_http_status(:success)
        expect(response.body).not_to include("property-positions")
        expect(response.body).not_to include("property-card")
        expect(response.body).not_to include("Immobilier par bien")
      end
    end

    describe "on the summary page" do
      it "keeps the immobilier view off the default tab" do
        bs = build_property_sheet(with_unassigned: true)

        get summary_balance_sheet_path(bs)

        expect(response).to have_http_status(:success)
        doc = Nokogiri::HTML(response.body)
        expect(doc.at_css(".tab-link-active").text.strip).to eq("Synthèse")
        expect(doc.at_css(".summary-column-assets")).not_to be_nil
        expect(response.body).not_to include("real-estate-table")
        expect(response.body).not_to include("Total immobilier")
      end

      describe "stepping between bilans" do
        it "links each arrow to the neighbouring bilan" do
          older = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
          current = create(:balance_sheet, user: user, closing_date: Date.new(2026, 6, 30))
          newer = create(:balance_sheet, user: user, closing_date: Date.new(2026, 12, 31))

          get summary_balance_sheet_path(current)

          doc = Nokogiri::HTML(response.body)
          expect(doc.at_css(".summary-nav a[rel=prev]")["href"]).to eq(summary_balance_sheet_path(older))
          expect(doc.at_css(".summary-nav a[rel=next]")["href"]).to eq(summary_balance_sheet_path(newer))
        end

        it "hands both arrows to the keyboard controller" do
          create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
          current = create(:balance_sheet, user: user, closing_date: Date.new(2026, 6, 30))
          create(:balance_sheet, user: user, closing_date: Date.new(2026, 12, 31))

          get summary_balance_sheet_path(current)

          doc = Nokogiri::HTML(response.body)
          expect(doc.at_css(".summary-nav")["data-controller"]).to eq("sheet-nav")
          expect(doc.at_css("a[data-sheet-nav-target=previous]")["rel"]).to eq("prev")
          expect(doc.at_css("a[data-sheet-nav-target=following]")["rel"]).to eq("next")
        end

        it "keeps the active tab on both arrows" do
          create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
          current = create(:balance_sheet, user: user, closing_date: Date.new(2026, 6, 30))
          create(:balance_sheet, user: user, closing_date: Date.new(2026, 12, 31))

          get summary_balance_sheet_path(current, tab: "real_estate")

          doc = Nokogiri::HTML(response.body)
          hrefs = doc.css(".summary-nav a").map { |link| link["href"] }
          expect(hrefs.size).to eq(2)
          expect(hrefs).to all(include("tab=real_estate"))
        end

        it "disables the arrow that has no bilan on its side" do
          only = create(:balance_sheet, user: user, closing_date: Date.new(2026, 6, 30))

          get summary_balance_sheet_path(only)

          doc = Nokogiri::HTML(response.body)
          expect(doc.css(".summary-nav a")).to be_empty
          expect(doc.css(".summary-nav .summary-nav-arrow-disabled").size).to eq(2)
        end

        it "ignores the bilans of another user" do
          current = create(:balance_sheet, user: user, closing_date: Date.new(2026, 6, 30))
          other = create(:user)
          create(:balance_sheet, user: other, closing_date: Date.new(2026, 12, 31))

          get summary_balance_sheet_path(current)

          expect(Nokogiri::HTML(response.body).css(".summary-nav a")).to be_empty
        end
      end

      it "falls back to the synthèse tab on an unknown tab value" do
        bs = build_property_sheet

        get summary_balance_sheet_path(bs, tab: "xyz")

        expect(response).to have_http_status(:success)
        doc = Nokogiri::HTML(response.body)
        expect(doc.at_css(".tab-link-active").text.strip).to eq("Synthèse")
        expect(doc.at_css(".summary-column-assets")).not_to be_nil
        expect(response.body).not_to include("real-estate-table")
      end

      describe "on the graphiques tab" do
        it "renders the bilan as charts instead of tables" do
          bs = build_property_sheet

          get summary_balance_sheet_path(bs, tab: "dashboard")

          expect(response).to have_http_status(:success)
          doc = Nokogiri::HTML(response.body)
          expect(doc.at_css(".tab-link-active").text.strip).to eq("Graphiques")
          expect(doc.at_css(".summary-column-assets")).to be_nil
          expect(doc.at_css(".real-estate-table")).to be_nil
          expect(doc.css(".chart-donut").size).to eq(2)
        end

        # L'onglet ne recalcule rien : il doit dire exactement ce que la synthèse dit. Les
        # deux totaux que découpent les anneaux se lisent au CENTRE de ceux-ci ; seuls les
        # fonds propres, que ni l'un ni l'autre ne totalise, gardent leur tuile.
        it "headlines the same three totals as the synthèse" do
          bs = build_property_sheet

          get summary_balance_sheet_path(bs, tab: "dashboard")

          doc = Nokogiri::HTML(response.body)
          expect(doc.css(".stat-grid .stat-value").map { |value| value.text.strip })
            .to eq([currency(50_000)])
          expect(doc.css(".chart-donut-total").map { |total| total.text.strip })
            .to eq([variation_currency(200_000), variation_currency(150_000)])
        end

        # Un anneau ne dit qu'une composition : deux patrimoines sans rapport y dessinent le
        # même camembert. Le total au centre dit de quelle somme il s'agit, et les deux
        # écarts d'où elle vient — sans quoi il faudrait retourner à la synthèse pour le
        # savoir, et les tuiles supprimées n'auraient fait que déménager.
        it "reads each total against the previous bilan and the one a year back" do
          create_sheet_worth(Date.new(2024, 12, 31), value: 100_000, debt: 90_000)
          create_sheet_worth(Date.new(2025, 6, 30), value: 150_000, debt: 80_000)
          current = create_sheet_worth(Date.new(2025, 12, 31), value: 200_000, debt: 70_000)

          get summary_balance_sheet_path(current, tab: "dashboard")

          assets, liabilities = Nokogiri::HTML(response.body).css(".chart-donut-center")
          expect(assets.css(".chart-donut-note").map { |note| note.text.split.join(" ") })
            .to eq(["#{previous_label} +#{variation_currency(50_000)} (+33,3 %)",
                    "#{yearly_label} +#{variation_currency(100_000)} (+100,0 %)"])
          # Une dette qui recule est une bonne nouvelle : le signe suit le montant, la
          # couleur suit la lecture.
          expect(liabilities.css(".chart-donut-note .variation").map { |note| note["class"] })
            .to eq(["variation variation-gain", "variation variation-gain"])
        end

        # Le premier bilan de l'historique n'a rien à comparer, et le trou de l'anneau est
        # trop étroit pour y écrire pourquoi : la ligne saute plutôt que d'annoncer un tiret.
        it "leaves the ring bare of any note on the very first bilan" do
          bs = create_sheet_worth(Date.new(2025, 12, 31), value: 200_000)

          get summary_balance_sheet_path(bs, tab: "dashboard")

          doc = Nokogiri::HTML(response.body)
          expect(doc.at_css(".chart-donut-total").text.strip).to eq(variation_currency(200_000))
          expect(doc.css(".chart-donut-note")).to be_empty
        end

        # Le détail par niveau de risque se lit dans la synthèse, qui le tient en toutes
        # lettres : le répéter en barres ici allongeait la page sans rien y ajouter.
        it "no longer breaks the actifs down by niveau de risque" do
          bs = build_property_sheet

          get summary_balance_sheet_path(bs, tab: "dashboard")

          expect(response.body).not_to include("Actifs par niveau de risque")
        end

        # Les parts de l'anneau sont des cercles en pointillés : sans le trait d'union dans
        # les noms d'attributs, le navigateur les ignore en silence et les parts se
        # superposent en un unique cercle fin. Rien dans le HTML ne le trahirait sans cela.
        it "gives each slice of the ring its own arc" do
          bs = create(:balance_sheet, user: user)
          create(:balance_sheet_asset, balance_sheet: bs,
                                       asset: create(:asset, user: user, asset_type: :savings_account),
                                       value: 30_000)
          create(:balance_sheet_asset, balance_sheet: bs,
                                       asset: create(:asset, user: user, asset_type: :financial_investment),
                                       value: 10_000)

          get summary_balance_sheet_path(bs, tab: "dashboard")

          slices = Nokogiri::HTML(response.body).css(".chart-donut-ring .chart-slice")
          expect(slices.size).to eq(2)
          expect(slices.map { |slice| slice["stroke-width"] }).to all(be_present)
          # Trois quarts du tour pour la part de 75 %, et un décalage nul pour la première.
          expect(slices.first["stroke-dasharray"].split.first.to_f)
            .to be_within(0.5).of(2 * Math::PI * 75 * 0.75)
          expect(slices.first["stroke-dashoffset"].to_f).to eq(0)
          expect(slices.last["stroke-dashoffset"].to_f).to be < 0
        end

        # Les anneaux et le miroir d'accueil ne racontent le patrimoine que s'ils le découpent
        # pareil : même catégorie, même clé, donc même teinte d'un écran à l'autre. Un anneau
        # redécoupé sur les types d'enum donnerait au livret la couleur que le miroir donne
        # aux placements, et la lecture croisée serait fausse sans que rien ne le dise.
        it "colours the rings on the same categories as the tableau de bord" do
          bs = build_property_sheet
          create(:balance_sheet_asset, balance_sheet: bs,
                                       asset: create(:asset, user: user, asset_type: :savings_account),
                                       value: 20_000)

          get summary_balance_sheet_path(bs, tab: "dashboard")

          doc = Nokogiri::HTML(response.body)
          assets, liabilities = doc.css(".chart-donut")
          expect(assets.css(".chart-donut-ring .chart-slice").map { |slice| slice["class"] })
            .to eq(["chart-slice chart-series-liquidity",
                    "chart-slice chart-series-real-estate-rental"])
          expect(liabilities.css(".chart-donut-ring .chart-slice").map { |slice| slice["class"] })
            .to eq(["chart-slice chart-series-real-estate-loan-rental"])
          # La pastille de la légende porte la même classe que sa part : c'est par elle que
          # la couleur se nomme, et les deux la lisent au même endroit.
          expect(assets.css(".chart-legend-swatch").map { |swatch| swatch["class"] })
            .to eq(["chart-legend-swatch chart-series-liquidity",
                    "chart-legend-swatch chart-series-real-estate-rental"])
        end

        # L'immobilier passe en titre de section dès qu'il montre plusieurs usages, comme dans
        # la légende du miroir : « Immobilier » écrit une fois, ses usages dessous.
        it "names the categories as the tableau de bord names them" do
          bs = build_property_sheet(with_unassigned: true)

          get summary_balance_sheet_path(bs, tab: "dashboard")

          legend = Nokogiri::HTML(response.body).at_css(".chart-donut .chart-legend")
          expect(legend.at_css(".chart-legend-group-title").text.strip).to eq("Immobilier")
          expect(legend.css(".chart-legend-sublist .chart-legend-label").map { |label| label.text.strip })
            .to eq(["Locatif", "Non rattaché"])
        end

        it "draws one bar per bien, read on its valeur nette" do
          bs = build_property_sheet

          get summary_balance_sheet_path(bs, tab: "dashboard")

          row = Nokogiri::HTML(response.body).css(".bar-breakdown").last.at_css(".bar-breakdown-row")
          expect(row.at_css(".bar-breakdown-label").text.strip).to eq("Appartement Lyon")
          expect(row.at_css(".bar-breakdown-amount").text.strip).to eq(currency(50_000))
        end

        it "keeps the tab when stepping to a neighbouring bilan" do
          older = create(:balance_sheet, user: user, closing_date: Date.new(2025, 6, 30))
          current = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))

          get summary_balance_sheet_path(current, tab: "dashboard")

          doc = Nokogiri::HTML(response.body)
          expect(doc.at_css(".summary-nav a[rel=prev]")["href"])
            .to eq(summary_balance_sheet_path(older, tab: "dashboard"))
        end
      end

      describe "on the immobilier tab" do
        it "shows the immobilier table instead of the actifs/passifs columns" do
          bs = build_property_sheet

          get summary_balance_sheet_path(bs, tab: "real_estate")

          expect(response).to have_http_status(:success)
          doc = Nokogiri::HTML(response.body)
          expect(doc.at_css(".tab-link-active").text.strip).to eq("Immobilier")
          expect(doc.at_css(".summary-column-assets")).to be_nil
          expect(doc.at_css(".real-estate-table")).not_to be_nil
          expect(response.body).not_to include("property-card")
          expect(response.body).not_to include("<details")
        end

        it "interleaves each usage subtotal row with its bien rows, in usage order" do
          bs = build_property_sheet
          home = create(:property, user: user, name: "Maison Annecy", usage: :primary_residence)
          home_asset = create(:asset, user: user, name: "Maison", asset_type: :real_estate, property: home)
          create(:balance_sheet_asset, balance_sheet: bs, asset: home_asset, value: 300_000)

          get summary_balance_sheet_path(bs, tab: "real_estate")

          expect(response).to have_http_status(:success)
          rows = Nokogiri::HTML(response.body).css(".real-estate-table tbody tr")

          expect(rows.map { |row| row["class"].to_s[/property-\S+-row/] }).to eq(
            ["property-usage-row", "property-bien-row", "property-usage-row", "property-bien-row", "property-totals-row"]
          )
          expect(rows.map { |row| row.at_css("td").text.gsub(/\s+/, " ").strip }).to eq(
            ["Résidence principale", "Maison Annecy", "Locatif", "Appartement Lyon", "Total immobilier"]
          )
        end

        it "carries the usage subtotal and the bien amounts on their own rows" do
          bs = build_property_sheet

          get summary_balance_sheet_path(bs, tab: "real_estate")

          expect(response).to have_http_status(:success)
          rows = Nokogiri::HTML(response.body).css(".real-estate-table tbody tr")
          cells = ->(row) { row.css("td").map { |cell| cell.text.gsub(/\s+/, " ").strip } }
          amounts = [currency(200_000), currency(150_000), currency(50_000), "75,0 %"].map { |v| v.gsub(/\s+/, " ") }

          usage_row = rows.first
          expect(usage_row.at_css(".badge").text.strip).to eq("Locatif")
          expect(cells.call(usage_row)).to eq(["Locatif"] + amounts)
          expect(cells.call(rows[1])).to eq(["Appartement Lyon"] + amounts)
        end

        it "sums several biens of the same usage into the subtotal, each row keeping its own amounts" do
          bs = build_property_sheet
          studio = create(:property, user: user, name: "Studio Grenoble", usage: :rental)
          studio_asset = create(:asset, user: user, name: "Studio", asset_type: :real_estate, property: studio)
          studio_loan = create(:liability, user: user, name: "Prêt Grenoble", liability_type: :real_estate_loan, property: studio)
          create(:balance_sheet_asset, balance_sheet: bs, asset: studio_asset, value: 100_000)
          create(:balance_sheet_liability, balance_sheet: bs, liability: studio_loan, remaining_capital: 90_000)

          get summary_balance_sheet_path(bs, tab: "real_estate")

          expect(response).to have_http_status(:success)
          rows = Nokogiri::HTML(response.body).css(".real-estate-table tbody tr")
          cells = ->(row) { row.css("td").map { |cell| cell.text.gsub(/\s+/, " ").strip } }
          amounts = ->(values) { values.map { |v| v.gsub(/\s+/, " ") } }

          expect(cells.call(rows[0])).to eq(
            ["Locatif"] + amounts.call([currency(300_000), currency(240_000), currency(60_000), "80,0 %"])
          )
          expect(cells.call(rows[1])).to eq(
            ["Appartement Lyon"] + amounts.call([currency(200_000), currency(150_000), currency(50_000), "75,0 %"])
          )
          expect(cells.call(rows[2])).to eq(
            ["Studio Grenoble"] + amounts.call([currency(100_000), currency(90_000), currency(10_000), "90,0 %"])
          )
        end

        it "derives the overall LTV on the total row" do
          bs = build_property_sheet

          get summary_balance_sheet_path(bs, tab: "real_estate")

          row = Nokogiri::HTML(response.body).at_css(".property-totals-row")

          expect(row.text).to include("Total immobilier")
          expect(row.css("td").last.text.gsub(/\s+/, " ").strip).to eq("75,0 %")
        end

        it "leaves the unassigned lines out of the rows and of the totals" do
          bs = build_property_sheet(with_unassigned: true)

          get summary_balance_sheet_path(bs, tab: "real_estate")

          expect(response).to have_http_status(:success)
          expect(response.body).not_to include("Non rattaché")
          expect(response.body).not_to include("Terrain orphelin")

          doc = Nokogiri::HTML(response.body)
          labels = doc.css(".real-estate-table tbody tr").map { |row| row.at_css("td").text.gsub(/\s+/, " ").strip }
          expect(labels).to eq(["Locatif", "Appartement Lyon", "Total immobilier"])

          # The 40k orphan asset does not inflate the total: it only counts 200k of gross.
          total_cells = doc.at_css(".property-totals-row").css("td").map { |cell| cell.text.gsub(/\s+/, " ").strip }
          expect(total_cells).to eq(
            ["Total immobilier", currency(200_000), currency(150_000), currency(50_000), "75,0 %"].map { |v| v.gsub(/\s+/, " ") }
          )
        end

        it "shows the empty state when only unassigned lines exist" do
          bs = create(:balance_sheet, user: user)
          orphan = create(:asset, user: user, name: "Terrain orphelin", asset_type: :real_estate)
          loan = create(:liability, user: user, name: "Prêt sans bien", liability_type: :real_estate_loan)
          create(:balance_sheet_asset, balance_sheet: bs, asset: orphan, value: 40_000)
          create(:balance_sheet_liability, balance_sheet: bs, liability: loan, remaining_capital: 30_000)

          get summary_balance_sheet_path(bs, tab: "real_estate")

          expect(response).to have_http_status(:success)
          expect(response.body).not_to include("real-estate-table")
          expect(response.body).to include("Aucun bien immobilier sur ce bilan.")
        end

        it "shows an empty state when the balance sheet has no real estate line" do
          bs = create(:balance_sheet, user: user)
          cash = create(:asset, user: user, name: "Livret A", asset_type: :savings_account)
          create(:balance_sheet_asset, balance_sheet: bs, asset: cash, value: 5_000)

          get summary_balance_sheet_path(bs, tab: "real_estate")

          expect(response).to have_http_status(:success)
          expect(response.body).not_to include("real-estate-table")
          expect(response.body).to include("Aucun bien immobilier sur ce bilan.")
        end
      end
    end
  end

  describe "POST /balance_sheets" do
    it "creates a new balance sheet" do
      expect {
        post balance_sheets_path, params: { balance_sheet: { closing_date: "2025-12-31" } }
      }.to change(BalanceSheet, :count).by(1)
    end
  end

  describe "duplicating a balance sheet" do
    let(:asset) { create(:asset, user: user, name: "Livret A") }
    let(:liability) { create(:liability, user: user, name: "Prêt") }
    let!(:source) do
      create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31)).tap do |bs|
        create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 12_000)
        create(:balance_sheet_liability, balance_sheet: bs, liability: liability, remaining_capital: 90_000)
      end
    end

    it "offers a duplicate link for each balance sheet on the index" do
      get balance_sheets_path

      doc = Nokogiri::HTML(response.body)
      expect(doc.css("a[href='#{new_balance_sheet_path(source_id: source.id)}']")).not_to be_empty
    end

    it "prefills the form and carries the source" do
      get new_balance_sheet_path(source_id: source.id)

      expect(response).to have_http_status(:success)
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("input[name='source_id']")["value"]).to eq(source.id.to_s)
    end

    it "copies every asset and liability line onto the new balance sheet" do
      expect {
        post balance_sheets_path, params: { balance_sheet: { closing_date: "2026-06-30" }, source_id: source.id }
      }.to change(BalanceSheet, :count).by(1)

      copy = BalanceSheet.order(:created_at).last
      expect(response).to redirect_to(copy)
      expect(copy.closing_date).to eq(Date.new(2026, 6, 30))
      expect(copy.balance_sheet_assets.pluck(:asset_id, :value)).to eq([[asset.id, 12_000]])
      expect(copy.balance_sheet_liabilities.pluck(:liability_id, :remaining_capital)).to eq([[liability.id, 90_000]])
      expect(source.reload.balance_sheet_assets.count).to eq(1)
    end

    it "projects the CRD of an amortizable loan to the new closing date instead of copying it" do
      loan = create(:liability, :amortizable, user: user, name: "Prêt amortissable")
      create(:balance_sheet_liability, balance_sheet: source, liability: loan, remaining_capital: 123_456)

      post balance_sheets_path, params: { balance_sheet: { closing_date: "2026-06-30" }, source_id: source.id }

      copy = BalanceSheet.order(:created_at).last
      copied_loan_line = copy.balance_sheet_liabilities.find_by(liability_id: loan.id)

      expect(copied_loan_line.remaining_capital).to eq(loan.suggested_remaining_capital(Date.new(2026, 6, 30)))
      expect(copied_loan_line.remaining_capital).not_to eq(123_456)
      expect(copied_loan_line.remaining_capital).to be_between(0, 200_000)

      # Le passif sans tableau d'amortissement reste copié tel quel.
      plain_line = copy.balance_sheet_liabilities.find_by(liability_id: liability.id)
      expect(plain_line.remaining_capital).to eq(90_000)
    end

    it "does not copy anything when the closing date is already taken" do
      expect {
        post balance_sheets_path, params: { balance_sheet: { closing_date: "2025-12-31" }, source_id: source.id }
      }.not_to change(BalanceSheetAsset, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "does not let a user duplicate someone else's balance sheet" do
      other = create(:balance_sheet, user: create(:user))

      get new_balance_sheet_path(source_id: other.id)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("flash.errors.not_found"))

      expect {
        post balance_sheets_path, params: { balance_sheet: { closing_date: "2027-01-31" }, source_id: other.id }
      }.not_to change(BalanceSheetAsset, :count)
    end
  end

  describe "GET /balance_sheets/:id/summary" do
    it "returns success" do
      bs = create(:balance_sheet, user: user)
      get summary_balance_sheet_path(bs)
      expect(response).to have_http_status(:success)
    end

    it "omits the risk breakdown headings when the balance sheet is empty" do
      bs = create(:balance_sheet, user: user)

      get summary_balance_sheet_path(bs)

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("Répartition par risque")
    end

    it "groups assets and liabilities by type" do
      bs = create(:balance_sheet, user: user)
      cash = create(:asset, user: user, name: "Espèces", asset_type: :cash, risk_level: :low)
      immo = create(:asset, user: user, name: "Maison", asset_type: :real_estate, risk_level: :medium)
      debt = create(:liability, user: user, name: "Prêt", risk_level: :low, liability_type: :real_estate_loan)
      create(:balance_sheet_asset, balance_sheet: bs, asset: cash, value: 1_000)
      create(:balance_sheet_asset, balance_sheet: bs, asset: immo, value: 200_000)
      create(:balance_sheet_liability, balance_sheet: bs, liability: debt, remaining_capital: 150_000)

      get summary_balance_sheet_path(bs)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Cash")
      expect(response.body).to include("Immobilier")
      expect(response.body).to include("Prêt")
      expect(response.body).to include("Crédit immobilier")
      expect(response.body).to include("Répartition par risque")
    end

    it "collapses each category behind its total amount" do
      bs = create(:balance_sheet, user: user)
      livret = create(:asset, user: user, name: "Livret A", asset_type: :cash)
      compte = create(:asset, user: user, name: "Compte courant", asset_type: :cash)
      create(:balance_sheet_asset, balance_sheet: bs, asset: livret, value: 1_000)
      create(:balance_sheet_asset, balance_sheet: bs, asset: compte, value: 500)

      get summary_balance_sheet_path(bs)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("summary-category-amount")
      expect(response.body).to include(currency(1_500))
      expect(response.body).not_to include("Sous-total")
      expect(response.body).not_to match(/<details class="summary-category" open/)
    end

    it "renders the owned amount for a partially owned asset" do
      bs = create(:balance_sheet, user: user)
      asset = create(:asset, user: user, name: "Maison", asset_type: :real_estate, ownership_share: 50)
      create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 200_000)

      get summary_balance_sheet_path(bs)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(currency(100_000))
      expect(response.body).not_to include(currency(200_000))
    end
  end

  describe "the évolution against the previous balance sheet" do
    # 100k of actifs and 60k of dettes last year, 120k and 50k this year: +20k of actifs,
    # -10k of dettes, and fonds propres from 40k to 70k.
    def build_two_sheets
      previous = create(:balance_sheet, user: user, closing_date: Date.new(2024, 12, 31))
      bs = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
      asset = create(:asset, user: user, name: "Livret A", asset_type: :savings_account)
      loan = create(:liability, user: user, name: "Prêt conso", liability_type: :short_term_debt)
      create(:balance_sheet_asset, balance_sheet: previous, asset: asset, value: 100_000)
      create(:balance_sheet_liability, balance_sheet: previous, liability: loan, remaining_capital: 60_000)
      create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 120_000)
      create(:balance_sheet_liability, balance_sheet: bs, liability: loan, remaining_capital: 50_000)

      bs
    end

    def note(node)
      node&.at_css(".variation")&.text&.gsub(/\s+/, " ")&.strip
    end

    describe "on the synthèse tab" do
      it "hangs the gain and its rate under each total, and under the fonds propres" do
        get summary_balance_sheet_path(build_two_sheets)

        expect(response).to have_http_status(:success)
        doc = Nokogiri::HTML(response.body)

        expect(note(doc.at_css(".summary-total-assets"))).to eq("+#{variation_currency(20_000)} (+20,0 %)".gsub(/\s+/, " "))
        expect(note(doc.at_css(".summary-total-liabilities"))).to eq("-#{variation_currency(10_000)} (-16,7 %)".gsub(/\s+/, " "))
        expect(note(doc.at_css(".equity-box"))).to eq("+#{variation_currency(30_000)} (+75,0 %)".gsub(/\s+/, " "))
      end

      it "reads a dette qui baisse as the good news it is, and a dette qui monte as a loss" do
        get summary_balance_sheet_path(build_two_sheets)

        doc = Nokogiri::HTML(response.body)
        expect(doc.at_css(".summary-total-assets .variation")["class"]).to include("variation-gain")
        expect(doc.at_css(".summary-total-liabilities .variation")["class"]).to include("variation-gain")

        bs = create(:balance_sheet, user: user, closing_date: Date.new(2026, 12, 31))
        loan = user.liabilities.sole
        create(:balance_sheet_liability, balance_sheet: bs, liability: loan, remaining_capital: 80_000)

        get summary_balance_sheet_path(bs)

        doc = Nokogiri::HTML(response.body)
        expect(doc.at_css(".summary-total-liabilities .variation")["class"]).to include("variation-loss")
        expect(note(doc.at_css(".summary-total-liabilities"))).to eq("+#{variation_currency(30_000)} (+60,0 %)".gsub(/\s+/, " "))
      end

      it "names the balance sheet the évolution is measured against" do
        get summary_balance_sheet_path(build_two_sheets)

        expect(Nokogiri::HTML(response.body).at_css(".page-header-hint").text).to include("31 décembre 2024")
      end

      it "shows no évolution at all on the user's very first balance sheet" do
        bs = create(:balance_sheet, user: user, closing_date: Date.new(2024, 12, 31))
        asset = create(:asset, user: user, name: "Livret A", asset_type: :savings_account)
        create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 100_000)

        get summary_balance_sheet_path(bs)

        expect(response).to have_http_status(:success)
        doc = Nokogiri::HTML(response.body)
        expect(doc.css(".variation")).to be_empty
        expect(doc.at_css(".page-header-hint")).to be_nil
      end
    end

    describe "on the immobilier tab" do
      # The same bien on both sheets: 400k financed by 300k, then 420k financed by 280k,
      # so the valeur nette goes from 100k to 140k.
      def build_two_property_sheets
        previous = create(:balance_sheet, user: user, closing_date: Date.new(2024, 12, 31))
        bs = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
        property = create(:property, user: user, name: "Appartement Lyon", usage: :rental)
        asset = create(:asset, user: user, name: "Appartement", asset_type: :real_estate, property: property)
        loan = create(:liability, user: user, name: "Prêt Lyon", liability_type: :real_estate_loan, property: property)
        create(:balance_sheet_asset, balance_sheet: previous, asset: asset, value: 400_000)
        create(:balance_sheet_liability, balance_sheet: previous, liability: loan, remaining_capital: 300_000)
        create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 420_000)
        create(:balance_sheet_liability, balance_sheet: bs, liability: loan, remaining_capital: 280_000)

        bs
      end

      it "hangs the move of the whole patrimoine under the valeur nette of the total row" do
        get summary_balance_sheet_path(build_two_property_sheets, tab: "real_estate")

        expect(response).to have_http_status(:success)
        rows = Nokogiri::HTML(response.body).css(".real-estate-table tbody tr")

        expect(note(rows.last)).to eq("+#{variation_currency(40_000)} (+40,0 %)".gsub(/\s+/, " "))
        expect(rows.last.at_css(".variation").parent["class"]).to eq("amount-with-variation")
      end

      it "leaves the usage rows and the bien rows without any évolution" do
        bs = build_two_property_sheets
        studio = create(:property, user: user, name: "Studio Grenoble", usage: :rental)
        studio_asset = create(:asset, user: user, name: "Studio", asset_type: :real_estate, property: studio)
        create(:balance_sheet_asset, balance_sheet: bs, asset: studio_asset, value: 90_000)

        get summary_balance_sheet_path(bs, tab: "real_estate")

        doc = Nokogiri::HTML(response.body)
        rows = doc.css(".real-estate-table tbody tr")

        expect(doc.css(".real-estate-table thead th").size).to eq(5)
        expect(rows.map { |row| note(row) }).to eq([nil, nil, nil, "+#{variation_currency(130_000)} (+130,0 %)".gsub(/\s+/, " ")])
        expect(doc.css(".property-usage-row .variation")).to be_empty
        expect(doc.css(".property-bien-row .variation")).to be_empty
      end

      it "shows no évolution at all on the user's very first balance sheet" do
        bs = create(:balance_sheet, user: user, closing_date: Date.new(2024, 12, 31))
        property = create(:property, user: user, name: "Appartement Lyon", usage: :rental)
        asset = create(:asset, user: user, name: "Appartement", asset_type: :real_estate, property: property)
        create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 400_000)

        get summary_balance_sheet_path(bs, tab: "real_estate")

        expect(response).to have_http_status(:success)
        doc = Nokogiri::HTML(response.body)
        expect(doc.css(".real-estate-table thead th").size).to eq(5)
        expect(doc.css(".variation")).to be_empty
      end
    end
  end

  describe "authentication" do
    it "redirects unauthenticated users" do
      sign_out user
      get balance_sheets_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
