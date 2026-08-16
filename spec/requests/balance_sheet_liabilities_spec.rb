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
  end

  describe "POST /balance_sheets/:id/balance_sheet_liabilities" do
    it "creates the line for an available liability" do
      expect {
        post balance_sheet_balance_sheet_liabilities_path(balance_sheet),
             params: { balance_sheet_liability: { liability_id: free_liability.id, remaining_capital: 5_000 } }
      }.to change(BalanceSheetLiability, :count).by(1)

      expect(response).to redirect_to(balance_sheet)
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
