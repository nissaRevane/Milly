require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def currency(amount, **options)
    ActionController::Base.helpers.number_to_currency(amount, **options)
  end

  # Les libellés d'une des deux légendes, dans l'ordre où ils se lisent. Famille et usage
  # étant sur deux lignes, le texte les recolle : on le normalise pour le comparer.
  def legend_labels(doc, selector)
    doc.at_css(selector).css(".chart-legend-label").map { |label| label.text.squish }
  end

  # Les ordonnées d'une bande du graphique, lues dans son attribut d. En SVG l'axe des
  # ordonnées croît vers le BAS : au-dessus de l'axe des abscisses, c'est y plus petit.
  def band_ys(doc, tone)
    doc.at_css(".chart-series-area.#{tone}")["d"].scan(/[ML] [\d.-]+ ([\d.-]+)/).flatten.map(&:to_f)
  end

  # Le montant d'une graduation, écrit à partir du SEUL format exposé au contrôleur Stimulus :
  # c'est ainsi qu'il écrira les siennes quand masquer une catégorie changera l'échelle.
  def exposed_currency(money, amount)
    digits = amount.abs.round.to_s.reverse.scan(/\d{1,3}/).join(money["delimiter"]).reverse

    money["format"].sub("%n", (amount.negative? ? "-" : "") + digits).sub("%u", money["unit"])
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

    describe "the mirrored area chart" do
      it "stacks one band per grande famille, in a stable order" do
        sheet = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
        create(:balance_sheet_asset, balance_sheet: sheet,
                                     asset: create(:asset, user: user, asset_type: :savings_account),
                                     value: 30_000)
        create(:balance_sheet_asset, balance_sheet: sheet,
                                     asset: create(:asset, user: user, asset_type: :financial_investment),
                                     value: 10_000)

        get root_path

        bands = Nokogiri::HTML(response.body).css(".chart-area-mirror .chart-series-area")
        expect(bands.map { |band| band["class"] }).to eq([
          "chart-series-area chart-series-liquidity",
          "chart-series-area chart-series-financial-investment"
        ])
      end

      # La demande derrière ce graphique : lire d'un coup ce que l'on possède et ce que l'on
      # doit. Deux courbes côte à côte laissaient le rapprochement à l'œil du lecteur.
      it "draws the actifs above the axis and the dette below it, on one chart" do
        sheet = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
        create(:balance_sheet_asset, balance_sheet: sheet,
                                     asset: create(:asset, user: user, asset_type: :savings_account),
                                     value: 100_000)
        create(:balance_sheet_liability, balance_sheet: sheet,
                                         liability: create(:liability, user: user, liability_type: :short_term_debt),
                                         remaining_capital: 40_000)

        get root_path

        doc = Nokogiri::HTML(response.body)
        expect(doc.css(".chart-area-mirror").size).to eq(1)
        axis = doc.at_css(".chart-axis-rule")["y1"].to_f
        expect(band_ys(doc, "chart-series-liquidity").max).to be <= axis
        expect(band_ys(doc, "chart-series-short-term-debt").min).to be >= axis
      end

      # Une légende se lit de haut en bas ; la pile des actifs, elle, monte depuis l'axe. Les
      # deux ne coïncident qu'une fois l'actif inversé — sans quoi chaque ligne nommerait la
      # bande d'en face.
      it "lists the actifs legend from the top band down and the dette legend from the axis down" do
        sheet = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
        create(:balance_sheet_asset, balance_sheet: sheet,
                                     asset: create(:asset, user: user, asset_type: :savings_account),
                                     value: 30_000)
        create(:balance_sheet_asset, balance_sheet: sheet,
                                     asset: create(:asset, user: user, asset_type: :financial_investment),
                                     value: 10_000)
        create(:balance_sheet_liability, balance_sheet: sheet,
                                         liability: create(:liability, user: user, liability_type: :short_term_debt),
                                         remaining_capital: 5_000)
        create(:balance_sheet_liability, balance_sheet: sheet,
                                         liability: create(:liability, user: user, liability_type: :security_deposit),
                                         remaining_capital: 2_000)

        get root_path

        doc = Nokogiri::HTML(response.body)
        expect(legend_labels(doc, ".chart-legend-column-assets")).to eq(["Placements financiers", "Liquidités"])
        expect(legend_labels(doc, ".chart-legend-column-debt")).to eq(["Dettes diverses", "Dépôts de garantie"])
      end

      # « Immobilier » écrit une fois plutôt que trois : dès que deux usages d'une même famille
      # sont à l'écran, la famille passe en titre et ses usages se listent dessous.
      it "gathers the usages of a family under one section title" do
        sheet = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
        %i[primary_residence secondary_residence rental].each_with_index do |usage, index|
          property = create(:property, user: user, name: "Bien #{index}", usage: usage)
          create(:balance_sheet_asset, balance_sheet: sheet,
                                       asset: property.real_estate_asset,
                                       value: 100_000 + index * 1_000)
        end

        get root_path

        column = Nokogiri::HTML(response.body).at_css(".chart-legend-column-assets")
        expect(column.css(".chart-legend-group-title").map(&:text)).to eq(["Immobilier"])
        expect(column.css(".chart-legend-sublist .chart-legend-label").map(&:text))
          .to eq(["Locatif", "Résidence secondaire", "Résidence principale"])
      end

      # Un titre pour une seule ligne n'apprendrait rien : la famille reste alors sur l'entrée,
      # au-dessus de son usage.
      it "leaves a family showing a single usage on one entry, without a section" do
        sheet = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
        property = create(:property, user: user, name: "Maison", usage: :primary_residence)
        create(:balance_sheet_asset, balance_sheet: sheet,
                                     asset: property.real_estate_asset, value: 300_000)

        get root_path

        column = Nokogiri::HTML(response.body).at_css(".chart-legend-column-assets")
        expect(column.at_css(".chart-legend-group-title")).to be_nil
        expect(column.at_css(".chart-legend-label").text.squish).to eq("Immobilier Résidence principale")
      end

      # Une légende dit un ordre de grandeur : la place manque dans la colonne, et le centime
      # se lit dans les tableaux du bilan.
      it "rounds the legend to the euro and its share to the unit" do
        sheet = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
        create(:balance_sheet_asset, balance_sheet: sheet,
                                     asset: create(:asset, user: user, asset_type: :savings_account),
                                     value: 123_456.78)
        create(:balance_sheet_asset, balance_sheet: sheet,
                                     asset: create(:asset, user: user, asset_type: :financial_investment),
                                     value: 76_543.22)

        get root_path

        doc = Nokogiri::HTML(response.body)
        column = doc.at_css(".chart-legend-column-assets")
        expect(column.css(".chart-legend-amount").map(&:text))
          .to eq([currency(76_543, precision: 0), currency(123_457, precision: 0)])
        expect(column.css(".chart-legend-share").map(&:text)).to eq(["38 %", "62 %"])
      end

      # La légende se pose à côté du graphique, de part et d'autre de l'axe : elle a donc
      # besoin de savoir où l'axe tombe. Le helper le lui dit en --axis-share, et ce chiffre
      # doit désigner la même hauteur que la ligne qu'il a tracée.
      it "hands the legend the very height at which it drew the axis" do
        balance_sheet_worth(Date.new(2025, 12, 31), value: 100_000, debt: 40_000)

        get root_path

        doc = Nokogiri::HTML(response.body)
        expect(doc.at_css(".chart-with-legend .chart-legend-columns")).not_to be_nil
        share = doc.at_css(".chart-legend-columns")["style"][/--axis-share: ([\d.]+)%/, 1].to_f
        axis = doc.at_css(".chart-axis-rule")["y1"].to_f
        # Nokogiri parse le HTML, qui n'a pas d'attribut sensible à la casse : viewBox y arrive
        # en viewbox.
        height = doc.at_css(".chart-area-mirror")["viewbox"].split.last.to_f
        expect(share).to be_within(0.05).of(axis / height * 100)
      end

      # Les deux côtés partagent une seule échelle : sans quoi une bande deux fois plus haute
      # ne vaudrait pas deux fois plus d'argent, et le miroir mentirait sur le patrimoine net.
      it "puts the actifs and the dette on the same scale" do
        sheet = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
        create(:balance_sheet_asset, balance_sheet: sheet,
                                     asset: create(:asset, user: user, asset_type: :savings_account),
                                     value: 100_000)
        create(:balance_sheet_liability, balance_sheet: sheet,
                                         liability: create(:liability, user: user, liability_type: :short_term_debt),
                                         remaining_capital: 40_000)

        get root_path

        doc = Nokogiri::HTML(response.body)
        assets = band_ys(doc, "chart-series-liquidity")
        debt = band_ys(doc, "chart-series-short-term-debt")
        expect(assets.max - assets.min).to be_within(0.05).of((debt.max - debt.min) * 2.5)
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

        bands = Nokogiri::HTML(response.body).css(".chart-area-mirror .chart-series-area")
        expect(bands.map { |band| band["class"].split.last }).to eq(%w[
          chart-series-real-estate-primary-residence
          chart-series-real-estate-secondary-residence
          chart-series-real-estate-rental
        ])
      end

      it "carries the immobilier lines without a bien in a band of their own" do
        sheet = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
        orphan = create(:asset, user: user, name: "Terrain", asset_type: :real_estate)
        create(:balance_sheet_asset, balance_sheet: sheet, asset: orphan, value: 40_000)

        get root_path

        doc = Nokogiri::HTML(response.body)
        expect(doc.at_css(".chart-series-real-estate-unassigned")).not_to be_nil
        # La bande porte le libellé d'un seul tenant, la légende le coupe en deux lignes.
        expect(doc.css(".chart-series-area title").map(&:text)).to include("Immobilier · Non rattaché")
        expect(doc.css(".chart-legend-sublabel").map(&:text)).to include("Non rattaché")
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

      # Sous l'axe, les bandes s'empilent en s'éloignant de lui : le fourre-tout d'abord, les
      # crédits immobiliers en dernier, chacun avec son usage.
      it "splits the crédits immobiliers by usage and keeps the other passifs whole" do
        property = create(:property, user: user, name: "Locatif Lyon", usage: :rental)
        loan = create(:liability, user: user, liability_type: :real_estate_loan, property: property)
        deposit = create(:liability, user: user, liability_type: :security_deposit)
        sheet = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
        create(:balance_sheet_liability, balance_sheet: sheet, liability: loan, remaining_capital: 150_000)
        create(:balance_sheet_liability, balance_sheet: sheet, liability: deposit, remaining_capital: 1_200)

        get root_path

        bands = Nokogiri::HTML(response.body).css(".chart-area-mirror .chart-series-area")
                  .map { |band| band["class"].split.last }
        expect(bands).to eq(%w[chart-series-security-deposit chart-series-real-estate-loan-rental])
      end

      # Une légende par côté de l'axe : leurs pourcentages se lisent chacun sur le total de
      # leur propre côté et ne se compareraient pas dans une liste commune.
      it "says so plainly when the history carries no dette at all, and still draws the actifs" do
        balance_sheet_worth(Date.new(2025, 12, 31), value: 50_000)

        get root_path

        doc = Nokogiri::HTML(response.body)
        column = doc.css(".chart-legend-column").find { |c|
          c.at_css(".chart-legend-title")&.text == I18n.t("views.dashboard.liabilities_breakdown")
        }
        expect(column.at_css(".empty-state").text).to eq(I18n.t("views.dashboard.no_liabilities"))
        expect(column.at_css(".chart-legend")).to be_nil
        expect(doc.at_css(".chart-area-mirror")).not_to be_nil
      end

      it "says so plainly when the history carries neither actif nor dette" do
        create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))

        get root_path

        card = Nokogiri::HTML(response.body).css(".chart-card").find { |c|
          c.at_css(".chart-title")&.text == I18n.t("views.dashboard.breakdown")
        }
        expect(card.at_css(".empty-state").text).to eq(I18n.t("views.dashboard.no_breakdown"))
        expect(card.at_css(".chart-area-mirror")).to be_nil
      end

      # Masquer une catégorie au clic sur sa pastille est le seul geste que le serveur ne sait
      # pas rendre : la pile doit se refaire sans elle, dans le navigateur. Ces trois épreuves
      # gardent le contrat que le contrôleur Stimulus chart_series consomme.
      describe "masquer une catégorie" do
        it "makes the legend swatch a button that names the band it commands" do
          property = create(:property, user: user, name: "Locatif Lyon", usage: :rental)
          sheet = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
          create(:balance_sheet_asset, balance_sheet: sheet, asset: property.real_estate_asset, value: 300_000)

          get root_path

          doc = Nokogiri::HTML(response.body)
          item = doc.at_css(".chart-legend-item[data-series='real_estate:rental']")
          swatch = item.at_css("button.chart-legend-swatch")
          expect(swatch["aria-pressed"]).to eq("true")
          expect(swatch["aria-label"]).to eq(I18n.t("views.shared.toggle_series", label: "Immobilier · Locatif"))
          expect(swatch["data-action"]).to eq("chart-series#toggle")
          # La pastille commande une bande, et c'est la clé qui les rapproche.
          expect(doc.at_css(".chart-series-area[data-series='real_estate:rental']")).not_to be_nil
        end

        # Masquer une catégorie redéploie l'échelle sur ce qui reste, dans le navigateur : le
        # contrôleur redessine la grille, l'axe et les bandes. Il ne connaît pour cela ni les
        # marges du repère ni le pas de graduation — le serveur les lui passe. Relire les
        # graduations RENDUES à partir de ces seules données prouve que ce qu'il reçoit est
        # bien ce avec quoi le serveur a dessiné : un zoom repartira du même cadre.
        it "hands the client the frame and the scale the server itself drew with" do
          livret = create(:asset, user: user, asset_type: :savings_account)
          property = create(:property, user: user, name: "Locatif Lyon", usage: :rental)
          loan = create(:liability, user: user, liability_type: :real_estate_loan, property: property)
          [Date.new(2025, 6, 30), Date.new(2025, 12, 31)].each_with_index do |date, index|
            sheet = create(:balance_sheet, user: user, closing_date: date)
            create(:balance_sheet_asset, balance_sheet: sheet, asset: livret, value: 10_000 + index * 2_000)
            create(:balance_sheet_asset, balance_sheet: sheet, asset: property.real_estate_asset, value: 300_000)
            create(:balance_sheet_liability, balance_sheet: sheet, liability: loan, remaining_capital: 200_000 - index * 5_000)
          end

          get root_path

          doc = Nokogiri::HTML(response.body)
          root = doc.at_css(".chart-with-legend")
          frame = JSON.parse(root["data-chart-series-frame-value"])
          scale = JSON.parse(root["data-chart-series-scale-value"])
          money = JSON.parse(root["data-chart-series-currency-value"])
          ordinate = ->(amount) {
            span = (scale["high"] - scale["low"]).to_f
            ((frame["bottom"] - (amount - scale["low"]) / span * (frame["bottom"] - frame["top"])) * 100).round / 100.0
          }

          multiples = (scale["low"] / scale["step"]).round..(scale["high"] / scale["step"]).round
          rendered = doc.css("[data-chart-series-target='grid'] line").map { |line| line["y1"] }
                        .zip(doc.css("[data-chart-series-target='grid'] text").map(&:text))
          expect(rendered).to eq(multiples.map { |multiple|
            amount = multiple * scale["step"]
            [ordinate.call(amount).to_s, exposed_currency(money, amount)]
          })
          # L'axe, et la ligne de partage de la légende qui doit tomber avec lui.
          expect(doc.at_css("[data-chart-series-target='axis']")["y1"]).to eq(ordinate.call(0).to_s)
          expect(doc.at_css("[data-chart-series-target='legend']")["style"])
            .to eq("--axis-share: #{(ordinate.call(0) / frame['height'] * 100).round(2)}%")
        end

        # Le format des montants vient d'I18n, par le serveur, et non d'un Intl.NumberFormat :
        # un autre espace de milliers ou un autre arrondi et la grille changerait d'aspect au
        # premier clic.
        it "hands over a money format that writes what number_to_currency writes" do
          balance_sheet_worth(Date.new(2025, 12, 31), value: 250_000, debt: 100_000)

          get root_path

          money = JSON.parse(Nokogiri::HTML(response.body)
                               .at_css(".chart-with-legend")["data-chart-series-currency-value"])
          [0, 2_500, 250_000, 1_234_567, -1_000, -1_234_567].each do |amount|
            expect(exposed_currency(money, amount)).to eq(currency(amount, precision: 0))
          end
        end

        # La légende de l'anneau ne commande rien : un bouton y promettrait une bascule qui
        # n'arriverait jamais.
        it "leaves the donut legend a plain swatch" do
          sheet = create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
          create(:balance_sheet_asset, balance_sheet: sheet, asset: create(:asset, user: user), value: 50_000)

          get summary_balance_sheet_path(sheet, tab: "dashboard")

          doc = Nokogiri::HTML(response.body)
          expect(doc.css(".chart-legend-swatch")).not_to be_empty
          expect(doc.css("button.chart-legend-swatch")).to be_empty
        end
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
