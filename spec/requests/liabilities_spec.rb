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

    it "creates a liability with the submitted ownership share" do
      expect {
        post liabilities_path, params: {
          liability: { name: "Prêt", risk_level: "low", liability_type: "real_estate_loan", ownership_share: "60" }
        }
      }.to change(Liability, :count).by(1)

      expect(Liability.last.ownership_share).to eq(60.0)
      expect(response).to redirect_to(liabilities_path)
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
