require "rails_helper"

RSpec.describe "BalanceSheets", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /balance_sheets" do
    it "returns success" do
      get balance_sheets_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /balance_sheets/:id" do
    it "returns success" do
      bs = create(:balance_sheet, user: user)
      get balance_sheet_path(bs)
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /balance_sheets" do
    it "creates a new balance sheet" do
      expect {
        post balance_sheets_path, params: { balance_sheet: { closing_date: "2025-12-31" } }
      }.to change(BalanceSheet, :count).by(1)
    end
  end

  describe "GET /balance_sheets/:id/summary" do
    it "returns success" do
      bs = create(:balance_sheet, user: user)
      get summary_balance_sheet_path(bs)
      expect(response).to have_http_status(:success)
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
