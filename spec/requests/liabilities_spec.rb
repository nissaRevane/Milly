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
  end

  describe "GET /liabilities/new" do
    it "returns success" do
      get new_liability_path
      expect(response).to have_http_status(:success)
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
