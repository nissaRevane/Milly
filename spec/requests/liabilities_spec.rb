require "rails_helper"

RSpec.describe "Liabilities", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /liabilities" do
    it "returns success" do
      get liabilities_path
      expect(response).to have_http_status(:success)
    end

    it "orders liabilities by type, then risk level, then name" do
      create(:liability, user: user, name: "Zeta", liability_type: :real_estate_loan, risk_level: :low)
      create(:liability, user: user, name: "Aaa", liability_type: :real_estate_loan, risk_level: :low)
      create(:liability, user: user, name: "Beta", liability_type: :real_estate_loan, risk_level: :high)
      create(:liability, user: user, name: "Alpha", liability_type: :security_deposit, risk_level: :low)

      get liabilities_path

      positions = ["Aaa", "Zeta", "Beta", "Alpha"].map { |name| response.body.index(name) }
      expect(positions).to eq(positions.compact.sort)
    end

    it "colors the liability type badge with the risk level" do
      create(:liability, user: user, name: "Prêt", liability_type: :real_estate_loan, risk_level: :low)

      get liabilities_path

      expect(response.body).to include('<span class="badge badge-success" title="Faible">')
      expect(response.body).to include("Crédit immobilier")
    end

    it "renders the ownership share" do
      create(:liability, user: user, name: "Prêt", ownership_share: 60)

      get liabilities_path

      expect(response.body).to include("60 %")
    end

    it "filters the liabilities by type" do
      create(:liability, user: user, name: "Prêt", liability_type: :real_estate_loan)
      create(:liability, user: user, name: "Caution", liability_type: :security_deposit)

      get liabilities_path, params: { liability_type: "real_estate_loan" }

      expect(response.body).to include("Prêt")
      expect(response.body).not_to include("Caution")
    end

    it "wires the filter to auto-submit without an inline handler" do
      create(:liability, user: user)

      get liabilities_path

      expect(response.body).to include('data-controller="auto-submit"')
      expect(response.body).to include('data-action="change-&gt;auto-submit#submit"')
      expect(response.body).not_to include("onchange=")
    end

    it "ignores an unknown type filter" do
      create(:liability, user: user, name: "Prêt", liability_type: :real_estate_loan)
      create(:liability, user: user, name: "Caution", liability_type: :security_deposit)

      get liabilities_path, params: { liability_type: "not_a_type" }

      expect(response.body).to include("Prêt")
      expect(response.body).to include("Caution")
    end

    it "shows a filtered empty state when no liability matches the type" do
      create(:liability, user: user, name: "Caution", liability_type: :security_deposit)

      get liabilities_path, params: { liability_type: "real_estate_loan" }

      expect(response.body).to include("Aucun passif pour ce type.")
      expect(response.body).to include("Filtrer par type")
    end
  end

  describe "GET /liabilities/:id" do
    it "renders the fiche, whose facts are corrected in place" do
      liability = create(:liability, user: user, name: "Prêt maison", ownership_share: 60)

      get liability_path(liability)

      expect(response).to have_http_status(:success)
      doc = Nokogiri::HTML(response.body)

      # Le nom s'édite dans le titre, les autres faits dans la liste : chacun porte son
      # propre formulaire vers l'update, et aucun ne mène à une page de saisie séparée.
      expect(doc.at_css("h1 .inline-edit-trigger").text.strip).to eq("Prêt maison")
      forms = doc.css("form.inline-edit-form[action='#{liability_path(liability)}']")
      expect(forms.length).to be >= 6
      expect(doc.at_css("select#liability_liability_type")).not_to be_nil
      expect(doc.at_css("select#liability_risk_level")).not_to be_nil
      expect(doc.at_css("input#liability_ownership_share")).not_to be_nil
      expect(doc.at_css("input#liability_started_on")).not_to be_nil
      expect(doc.at_css("input#liability_ended_on")).not_to be_nil
      expect(response.body).to include("60 %")
    end

    # Chaque formulaire de la fiche renvoie l'onglet lu : on revient sur la facette qu'on
    # était en train de corriger, pas sur celle d'accueil.
    it "carries the tab it was read on in every inline form" do
      liability = create(:liability, :amortizable, user: user)

      get liability_path(liability, tab: "schedule")

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("form input[name='tab']")["value"]).to eq("schedule")
    end

    it "offers the fiche, the évolution and, on a crédit, the échéancier" do
      liability = create(:liability, user: user, liability_type: :real_estate_loan)

      get liability_path(liability)

      tabs = Nokogiri::HTML(response.body).css(".tab-nav .tab-link")
      expect(tabs.map { |tab| tab.text.strip }).to eq(["Fiche", "Évolution", "Échéancier"])
      expect(tabs.first["aria-current"]).to eq("page")
    end

    it "offers no échéancier tab for a type that carries none" do
      liability = create(:liability, user: user, liability_type: :security_deposit)

      get liability_path(liability)

      tabs = Nokogiri::HTML(response.body).css(".tab-nav .tab-link")
      expect(tabs.map { |tab| tab.text.strip }).to eq(["Fiche", "Évolution"])
    end

    # L'onglet demandé n'existe pas : la fiche répond, plutôt qu'une erreur ou un onglet vide.
    it "falls back to the fiche when the échéancier is asked of a type that carries none" do
      liability = create(:liability, user: user, liability_type: :security_deposit)

      get liability_path(liability, tab: "schedule")

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("amortization-table")
      expect(Nokogiri::HTML(response.body).at_css(".tab-link-active").text.strip).to eq("Fiche")
    end

    it "does not show another user's liability" do
      other = create(:liability, :amortizable, user: create(:user))

      get liability_path(other)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("flash.errors.not_found"))
    end
  end

  describe "the échéancier tab" do
    it "renders the amortization schedule of an amortizable loan" do
      liability = create(:liability, :amortizable, user: user, name: "Prêt maison")

      get liability_path(liability, tab: "schedule")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Prêt maison")

      doc = Nokogiri::HTML(response.body)
      expect(doc.css("h2").map(&:text).map(&:strip)).to include("Tableau d'amortissement")

      rows = doc.css(".amortization-table tbody tr")
      expect(rows.length).to eq(liability.amortization_schedule.rows.length)

      first_cells = rows.first.css("td").map { |cell| cell.text.gsub(/\s+/, " ").strip }
      currency = ->(amount) { ActionController::Base.helpers.number_to_currency(amount).gsub(/\s+/, " ") }
      expect(first_cells).to eq(["1", "05/03/2024", currency.call(312.50), currency.call(650), currency.call(199_350)])
    end

    it "renders the amortization schedule of an autre crédit" do
      liability = create(:liability, :amortizable, user: user, liability_type: :other_credit, name: "Prêt auto")

      get liability_path(liability, tab: "schedule")

      expect(response).to have_http_status(:success)
      expect(Nokogiri::HTML(response.body).css(".amortization-table tbody tr").length)
        .to eq(liability.amortization_schedule.rows.length)
    end

    # Les sept caractéristiques se saisissent en bloc : le formulaire est là, prérempli,
    # même quand aucune n'est renseignée — c'est le seul endroit d'où l'échéancier naît.
    it "offers the seven terms as one block, and says there is no schedule yet" do
      liability = create(:liability, user: user, liability_type: :real_estate_loan)

      get liability_path(liability, tab: "schedule")

      doc = Nokogiri::HTML(response.body)
      Liability::AMORTIZATION_FIELDS.each do |field|
        expect(doc.at_css("##{"liability_#{field}"}")).not_to be_nil
      end
      expect(doc.at_css(".empty-state").text)
        .to include("Aucun tableau d'amortissement pour l'instant")
      expect(response.body).not_to include("amortization-table")
    end

    it "defines a schedule from the terms submitted together, and comes back to the tab" do
      liability = create(:liability, user: user, liability_type: :real_estate_loan)

      patch liability_path(liability), params: {
        tab: "schedule",
        liability: {
          borrowed_capital: "200000", annual_rate: "3.125", duration_months: "240",
          monthly_payment: "1109.20", first_payment_on: "2024-03-05",
          first_payment_principal: "650", first_payment_interest: "312.50"
        }
      }

      expect(response).to redirect_to(liability_path(liability, tab: "schedule"))
      expect(liability.reload).to be_amortizable
    end
  end

  describe "the évolution tab" do
    it "reads the line's amounts bilan after bilan, with its two variations" do
      liability = create(:liability, user: user, name: "Prêt maison", ownership_share: 50)
      [[Date.new(2024, 6, 30), 200_000], [Date.new(2025, 6, 30), 190_000],
       [Date.new(2025, 12, 31), 180_000]].each do |date, capital|
        create(:balance_sheet_liability,
               balance_sheet: create(:balance_sheet, user: user, closing_date: date),
               liability: liability, remaining_capital: capital)
      end

      get liability_path(liability, tab: "history")

      expect(response).to have_http_status(:success)
      doc = Nokogiri::HTML(response.body)

      # Le montant lu est le capital DÉTENU, quote-part appliquée, comme sur le bilan.
      expect(doc.at_css(".stat-card-highlight .stat-value").text).to include("90 000")
      # Une dette qui baisse est une bonne nouvelle : la variation se lit en gain.
      expect(doc.css(".stat-card .variation-gain").length).to eq(2)
      expect(doc.css(".chart-line .chart-point").length).to eq(3)
    end

    it "says so when no bilan carries the liability yet" do
      liability = create(:liability, user: user)

      get liability_path(liability, tab: "history")

      expect(Nokogiri::HTML(response.body).at_css(".empty-state").text)
        .to include("Ce passif ne figure dans aucun bilan")
    end
  end

  describe "the link from the index to the show page" do
    it "links each liability name to its page" do
      liability = create(:liability, user: user, name: "Prêt")

      get liabilities_path

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("a[href='#{liability_path(liability)}']")&.text&.strip).to eq("Prêt")
    end
  end

  describe "GET /liabilities/new" do
    it "returns success" do
      get new_liability_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "the amortization fieldset visibility" do
    def amortization_fieldset
      Nokogiri::HTML(response.body).at_css("fieldset[data-conditional-fields-target='fields']")
    end

    it "shows the fieldset on the new form, where a real estate loan is preselected" do
      get new_liability_path

      expect(amortization_fieldset).not_to be_nil
      expect(amortization_fieldset.attribute("hidden")).to be_nil
      expect(response.body).to include('data-controller="conditional-fields"')
      expect(amortization_fieldset["data-conditional-fields-show-when"]).to eq("real_estate_loan other_credit")
    end

    # Sur la fiche, le serveur a déjà tranché : le bloc n'est pas masqué là, il est sur son
    # onglet ou il n'y est pas (voir « the échéancier tab »).
    it "leaves no conditional fieldset on the fiche" do
      liability = create(:liability, user: user, liability_type: :real_estate_loan)

      get liability_path(liability, tab: "schedule")

      expect(amortization_fieldset).to be_nil
      expect(response.body).not_to include('data-controller="conditional-fields"')
    end
  end

  describe "POST /liabilities" do
    it "creates a new liability" do
      expect {
        post liabilities_path, params: { liability: { name: "Prêt immobilier", risk_level: "low", liability_type: "real_estate_loan" } }
      }.to change(Liability, :count).by(1)

      expect(Liability.last.liability_type).to eq("real_estate_loan")
      expect(response).to redirect_to(liabilities_path)
    end

    it "creates a liability with its lifespan" do
      post liabilities_path, params: { liability: { name: "Prêt immobilier", risk_level: "low",
                                                   liability_type: "real_estate_loan",
                                                   started_on: "2020-02-01", ended_on: "2040-01-31" } }

      liability = Liability.last
      expect(liability.started_on).to eq(Date.new(2020, 2, 1))
      expect(liability.ended_on).to eq(Date.new(2040, 1, 31))
    end

    it "does not create with a lifespan ending before it starts" do
      expect {
        post liabilities_path, params: { liability: { name: "Prêt", risk_level: "low",
                                                     liability_type: "real_estate_loan",
                                                     started_on: "2020-06-01", ended_on: "2020-05-31" } }
      }.not_to change(Liability, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "does not create with an unknown liability type" do
      expect {
        post liabilities_path, params: { liability: { name: "X", risk_level: "low", liability_type: "bogus" } }
      }.not_to change(Liability, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "does not create with invalid params" do
      expect {
        post liabilities_path, params: { liability: { name: "", risk_level: "low" } }
      }.not_to change(Liability, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "creates a liability with the submitted ownership share" do
      expect {
        post liabilities_path, params: {
          liability: { name: "Prêt", risk_level: "low", liability_type: "real_estate_loan", ownership_share: "60" }
        }
      }.to change(Liability, :count).by(1)

      expect(Liability.last.ownership_share).to eq(60.0)
      expect(response).to redirect_to(liabilities_path)
    end

    it "creates a loan with its amortization terms" do
      expect {
        post liabilities_path, params: {
          liability: {
            name: "Prêt maison", risk_level: "low", liability_type: "real_estate_loan",
            borrowed_capital: "200000", annual_rate: "3.125", duration_months: "240",
            monthly_payment: "1109.20", first_payment_on: "2024-03-05",
            first_payment_principal: "650", first_payment_interest: "312.50"
          }
        }
      }.to change(Liability, :count).by(1)

      liability = Liability.last
      expect(liability).to be_amortizable
      expect(liability.annual_rate).to eq(BigDecimal("3.125"))
      expect(liability.duration_months).to eq(240)
      expect(response).to redirect_to(liabilities_path)
    end

    it "rejects a partial set of amortization terms" do
      expect {
        post liabilities_path, params: {
          liability: {
            name: "Prêt maison", risk_level: "low", liability_type: "real_estate_loan",
            borrowed_capital: "200000"
          }
        }
      }.not_to change(Liability, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "does not create with an ownership share above 100" do
      expect {
        post liabilities_path, params: {
          liability: { name: "Prêt", risk_level: "low", liability_type: "real_estate_loan", ownership_share: "150" }
        }
      }.not_to change(Liability, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "linking a liability to a property" do
    it "offers no property select when the user has no property" do
      get new_liability_path

      expect(response.body).not_to include("liability_property_id")
      expect(response.body).not_to include("Bien immobilier rattaché")
    end

    it "offers the user's properties ordered by usage then name" do
      create(:property, user: user, name: "Studio", usage: :rental)
      create(:property, user: user, name: "Maison", usage: :primary_residence)
      create(:property, user: create(:user), name: "Villa du voisin")

      get new_liability_path

      doc = Nokogiri::HTML(response.body)
      options = doc.css("select#liability_property_id option").map { |option| option.text.strip }

      expect(options).to eq(["Aucun bien", "Maison", "Studio"])
      expect(response.body).to include("Bien immobilier rattaché")
    end

    # Sur le formulaire de création, le champ apparaît selon le type choisi et le contrôleur
    # Stimulus lit la liste des types dans l'attribut data. Sur la fiche, le serveur a déjà
    # tranché : le fait est là, ou il n'y est pas.
    it "leaves the property fact off the fiche of a type no bien carries" do
      create(:property, user: user, name: "Maison")
      liability = create(:liability, user: user, liability_type: :short_term_debt)

      get liability_path(liability)

      expect(Nokogiri::HTML(response.body).at_css("select#liability_property_id")).to be_nil
      expect(response.body).not_to include("Bien immobilier rattaché")
    end

    it "shows the property fact on the fiche of a dépôt de garantie" do
      create(:property, user: user, name: "Maison", usage: :rental)
      liability = create(:liability, user: user, liability_type: :security_deposit)

      get liability_path(liability)

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("select#liability_property_id")).not_to be_nil
      expect(response.body).to include("Bien immobilier rattaché")
    end

    it "creates a liability linked to a property" do
      property = create(:property, user: user)

      post liabilities_path, params: {
        liability: { name: "Prêt", risk_level: "low", liability_type: "real_estate_loan", property_id: property.id }
      }

      expect(Liability.last.property).to eq(property)
      expect(response).to redirect_to(liabilities_path)
    end

    it "creates a dépôt de garantie linked to a property" do
      property = create(:property, user: user, usage: :rental)

      post liabilities_path, params: {
        liability: { name: "Dépôt Studio", risk_level: "low", liability_type: "security_deposit",
                     property_id: property.id }
      }

      expect(Liability.last.property).to eq(property)
      expect(response).to redirect_to(liabilities_path)
    end

    # Une dette court terme n'est portée par aucun bien : le rattachement soumis est ignoré,
    # comme le formulaire l'annonce en masquant le champ.
    it "drops the property submitted for a type no bien carries" do
      property = create(:property, user: user)

      post liabilities_path, params: {
        liability: { name: "Travaux", risk_level: "low", liability_type: "short_term_debt",
                     property_id: property.id }
      }

      expect(response).to redirect_to(liabilities_path)
      expect(Liability.find_by(name: "Travaux").property_id).to be_nil
    end

    # Le champ masqué ne renvoie rien : c'est le changement de type qui défait le
    # rattachement, sans quoi la validation refuserait un champ devenu invisible.
    it "unlinks a liability that leaves a type a bien carries" do
      property = create(:property, user: user)
      liability = create(:liability, user: user, property: property, liability_type: :real_estate_loan)

      patch liability_path(liability), params: { liability: { liability_type: "short_term_debt" } }

      expect(response).to redirect_to(liability_path(liability))
      liability.reload
      expect(liability.liability_type).to eq("short_term_debt")
      expect(liability.property_id).to be_nil
    end

    it "unlinks a liability when the blank option is submitted" do
      property = create(:property, user: user)
      liability = create(:liability, user: user, property: property)

      patch liability_path(liability), params: { liability: { property_id: "" } }

      expect(liability.reload.property_id).to be_nil
      expect(response).to redirect_to(liability_path(liability))
    end

    # See the assets spec: a forged property_id must never cross accounts.
    it "refuses to link a new liability to another user's property" do
      foreign = create(:property, user: create(:user), name: "Villa du voisin")

      post liabilities_path, params: {
        liability: { name: "Prêt", risk_level: "low", liability_type: "real_estate_loan", property_id: foreign.id }
      }

      expect(Liability.last.property_id).to be_nil
      expect(foreign.reload.liabilities).to be_empty
    end

    it "refuses to link an existing liability to another user's property" do
      liability = create(:liability, user: user)
      foreign = create(:property, user: create(:user), name: "Villa du voisin")

      patch liability_path(liability), params: { liability: { property_id: foreign.id } }

      expect(liability.reload.property_id).to be_nil
      expect(foreign.reload.liabilities).to be_empty
    end
  end

  describe "PATCH /liabilities/:id" do
    let(:liability) { create(:liability, user: user, name: "Old Name") }

    # La fiche est le formulaire : on revient dessus, sur l'onglet où l'on était, plutôt que
    # sur la liste — on corrige un champ pour continuer à lire le passif, pas pour le quitter.
    it "updates the ownership share and comes back to the fiche" do
      patch liability_path(liability), params: { liability: { ownership_share: "33.33" } }
      expect(liability.reload.ownership_share).to eq(BigDecimal("33.33"))
      expect(response).to redirect_to(liability_path(liability))
    end

    it "renders the fiche again with its errors when the update is refused" do
      patch liability_path(liability), params: { liability: { name: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(liability.reload.name).to eq("Old Name")
      expect(Nokogiri::HTML(response.body).at_css(".alert-danger").text)
        .to include("doit être rempli")
      # C'est bien la fiche qui répond, ses onglets compris.
      expect(response.body).to include("tab-nav")
    end
  end

  describe "DELETE /liabilities/:id" do
    it "destroys the liability" do
      liability = create(:liability, user: user)
      expect {
        delete liability_path(liability)
      }.to change(Liability, :count).by(-1)
    end
  end
end
