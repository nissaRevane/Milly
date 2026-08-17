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
    it "renders the amortization schedule of an amortizable loan" do
      liability = create(:liability, :amortizable, user: user, name: "Prêt maison")

      get liability_path(liability)

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

    it "shows a hint instead of a table when the liability carries no schedule" do
      liability = create(:liability, user: user, name: "Dette simple")

      get liability_path(liability)

      expect(response).to have_http_status(:success)
      hint = Nokogiri::HTML(response.body).at_css(".empty-state")
      expect(hint.text).to include("Aucun tableau d'amortissement défini pour ce passif.")
      expect(response.body).not_to include("amortization-table")
    end

    it "shows a neutral hint for liability types that cannot carry a schedule" do
      liability = create(:liability, user: user, liability_type: :security_deposit, name: "Caution")

      get liability_path(liability)

      expect(response).to have_http_status(:success)
      hint = Nokogiri::HTML(response.body).at_css(".empty-state")
      expect(hint.text).to include("Les tableaux d'amortissement ne concernent que les prêts immobiliers.")
      expect(hint.text).not_to include("Renseignez les caractéristiques du prêt")
      expect(response.body).not_to include("amortization-table")
    end

    it "does not show another user's liability" do
      other = create(:liability, :amortizable, user: create(:user))

      get liability_path(other)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("flash.errors.not_found"))
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
      expect(response.body).to include('data-conditional-fields-show-when-value="real_estate_loan"')
    end

    it "shows the fieldset when editing a real estate loan" do
      liability = create(:liability, user: user, liability_type: :real_estate_loan)

      get edit_liability_path(liability)

      expect(amortization_fieldset.attribute("hidden")).to be_nil
    end

    it "hides the fieldset when editing a liability of another type" do
      liability = create(:liability, user: user, liability_type: :security_deposit)

      get edit_liability_path(liability)

      expect(amortization_fieldset).not_to be_nil
      expect(amortization_fieldset.attribute("hidden")).not_to be_nil
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

    it "creates a liability linked to a property" do
      property = create(:property, user: user)

      post liabilities_path, params: {
        liability: { name: "Prêt", risk_level: "low", liability_type: "real_estate_loan", property_id: property.id }
      }

      expect(Liability.last.property).to eq(property)
      expect(response).to redirect_to(liabilities_path)
    end

    it "unlinks a liability when the blank option is submitted" do
      property = create(:property, user: user)
      liability = create(:liability, user: user, property: property)

      patch liability_path(liability), params: { liability: { property_id: "" } }

      expect(liability.reload.property_id).to be_nil
      expect(response).to redirect_to(liabilities_path)
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

    it "updates the ownership share" do
      patch liability_path(liability), params: { liability: { ownership_share: "33.33" } }
      expect(liability.reload.ownership_share).to eq(BigDecimal("33.33"))
      expect(response).to redirect_to(liabilities_path)
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
