require "rails_helper"

RSpec.describe "BalanceSheetLiabilities", type: :request do
  let(:user) { create(:user) }
  let(:balance_sheet) { create(:balance_sheet, user: user) }
  let!(:used_liability) { create(:liability, user: user, name: "Prêt immobilier") }
  let!(:free_liability) { create(:liability, user: user, name: "Prêt auto") }

  before do
    sign_in user
    create(:balance_sheet_liability, balance_sheet: balance_sheet, liability: used_liability)
  end

  describe "GET /balance_sheets/:id/balance_sheet_liabilities/new" do
    it "returns success" do
      get new_balance_sheet_balance_sheet_liability_path(balance_sheet)
      expect(response).to have_http_status(:success)
    end

    it "excludes liabilities already present in the balance sheet from the dropdown" do
      get new_balance_sheet_balance_sheet_liability_path(balance_sheet)

      expect(response.body).not_to include("value=\"#{used_liability.id}\"")
      expect(response.body).to include("value=\"#{free_liability.id}\"")
    end

    it "carries the projected CRD at the closing date as the suggested value of an amortizable loan" do
      sheet = create(:balance_sheet, user: user, closing_date: Date.new(2024, 4, 20))
      loan = create(:liability, :amortizable, user: user, name: "Prêt amortissable")

      get new_balance_sheet_balance_sheet_liability_path(sheet)

      # Deux échéances passées au 20/04/2024 : CRD = 198 739,18 € (voir amortization_schedule_spec).
      expect(response.body).to include(
        "<option data-suggested-value=\"198739.18\" value=\"#{loan.id}\">"
      )
    end

    it "carries no suggested value for a liability without amortization terms" do
      get new_balance_sheet_balance_sheet_liability_path(balance_sheet)

      expect(response.body).to include("<option value=\"#{free_liability.id}\">")
    end

    # Le défaut de colonne (0.0) remplirait le champ d'un montant que personne n'a saisi,
    # et le capital restant dû suggéré ne s'installerait plus.
    it "leaves the remaining capital field empty instead of pre-filling the column default" do
      get new_balance_sheet_balance_sheet_liability_path(balance_sheet)

      field = Nokogiri::HTML(response.body).at_css("#balance_sheet_liability_remaining_capital")

      expect(field["value"]).to be_nil
    end

    # Une dette éteinte ou pas encore née ne pèse pas sur ce bilan-là.
    it "excludes a liability outside its lifespan at the closing date" do
      future_loan = create(:liability, user: user, name: "Prêt futur",
                           started_on: balance_sheet.closing_date + 2.months)
      repaid_loan = create(:liability, user: user, name: "Prêt soldé",
                           ended_on: balance_sheet.closing_date - 2.months)

      get new_balance_sheet_balance_sheet_liability_path(balance_sheet)

      expect(response.body).not_to include("value=\"#{future_loan.id}\"")
      expect(response.body).not_to include("value=\"#{repaid_loan.id}\"")
    end

    # La tolérance du mois en cours : la comparaison se fait au mois, jamais au jour.
    it "keeps a liability that started or ended in the month of the closing date" do
      starting = create(:liability, user: user, name: "Souscrit",
                        started_on: balance_sheet.closing_date.end_of_month)
      ending = create(:liability, user: user, name: "Soldé",
                      ended_on: balance_sheet.closing_date.beginning_of_month)

      get new_balance_sheet_balance_sheet_liability_path(balance_sheet)

      expect(response.body).to include("value=\"#{starting.id}\"")
      expect(response.body).to include("value=\"#{ending.id}\"")
    end

    it "excludes liabilities belonging to another user" do
      other_liability = create(:liability, user: create(:user), name: "Autre")

      get new_balance_sheet_balance_sheet_liability_path(balance_sheet)

      expect(response.body).not_to include("value=\"#{other_liability.id}\"")
    end
  end

  describe "GET /balance_sheets/:id/balance_sheet_liabilities/:id/edit" do
    it "keeps the currently selected liability in the dropdown" do
      balance_sheet_liability = balance_sheet.balance_sheet_liabilities.first

      get edit_balance_sheet_balance_sheet_liability_path(balance_sheet, balance_sheet_liability)

      expect(response.body).to include("value=\"#{used_liability.id}\"")
      expect(response.body).to include("value=\"#{free_liability.id}\"")
    end

    # Voir BalanceSheetAssets : une ligne enregistrée est de l'histoire.
    it "keeps the currently selected liability even once it is out of its lifespan" do
      balance_sheet_liability = balance_sheet.balance_sheet_liabilities.first
      used_liability.update!(ended_on: balance_sheet.closing_date - 2.months)

      get edit_balance_sheet_balance_sheet_liability_path(balance_sheet, balance_sheet_liability)

      expect(response.body).to include("value=\"#{used_liability.id}\"")
    end
  end

  describe "POST /balance_sheets/:id/balance_sheet_liabilities" do
    it "creates the line for an available liability" do
      expect {
        post balance_sheet_balance_sheet_liabilities_path(balance_sheet),
             params: { balance_sheet_liability: { liability_id: free_liability.id, remaining_capital: 5_000 } }
      }.to change(BalanceSheetLiability, :count).by(1)

      expect(response).to redirect_to(balance_sheet)
    end

    it "rejects a liability outside its lifespan" do
      repaid_loan = create(:liability, user: user, ended_on: balance_sheet.closing_date - 2.months)

      expect {
        post balance_sheet_balance_sheet_liabilities_path(balance_sheet),
             params: { balance_sheet_liability: { liability_id: repaid_loan.id, remaining_capital: 5_000 } }
      }.not_to change(BalanceSheetLiability, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects a liability already present in the balance sheet" do
      expect {
        post balance_sheet_balance_sheet_liabilities_path(balance_sheet),
             params: { balance_sheet_liability: { liability_id: used_liability.id, remaining_capital: 5_000 } }
      }.not_to change(BalanceSheetLiability, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
