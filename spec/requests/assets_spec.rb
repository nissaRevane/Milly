require "rails_helper"

RSpec.describe "Assets", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /assets" do
    it "returns success" do
      get assets_path
      expect(response).to have_http_status(:success)
    end

    it "orders assets by type, then risk level, then name" do
      create(:asset, user: user, name: "Zeta", asset_type: :checking_account, risk_level: :low)
      create(:asset, user: user, name: "Aaa", asset_type: :checking_account, risk_level: :low)
      create(:asset, user: user, name: "Beta", asset_type: :checking_account, risk_level: :high)
      create(:asset, user: user, name: "Alpha", asset_type: :real_estate, risk_level: :low)

      get assets_path

      positions = ["Aaa", "Zeta", "Beta", "Alpha"].map { |name| response.body.index(name) }
      expect(positions).to eq(positions.compact.sort)
    end
  end

  describe "GET /assets/new" do
    it "returns success" do
      get new_asset_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /assets" do
    it "creates a new asset" do
      expect {
        post assets_path, params: { asset: { name: "Livret A", risk_level: "low", asset_type: "savings_account" } }
      }.to change(Asset, :count).by(1)

      expect(Asset.last.asset_type).to eq("savings_account")
      expect(response).to redirect_to(assets_path)
    end

    it "does not create with invalid params" do
      expect {
        post assets_path, params: { asset: { name: "", risk_level: "low" } }
      }.not_to change(Asset, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /assets/:id" do
    let(:asset) { create(:asset, user: user, name: "Old Name") }

    it "updates the asset" do
      patch asset_path(asset), params: { asset: { name: "New Name" } }
      expect(asset.reload.name).to eq("New Name")
      expect(response).to redirect_to(assets_path)
    end

    it "updates the asset type" do
      patch asset_path(asset), params: { asset: { asset_type: "real_estate" } }
      expect(asset.reload.asset_type).to eq("real_estate")
      expect(response).to redirect_to(assets_path)
    end
  end

  describe "DELETE /assets/:id" do
    it "destroys the asset" do
      asset = create(:asset, user: user)
      expect {
        delete asset_path(asset)
      }.to change(Asset, :count).by(-1)

      expect(response).to redirect_to(assets_path)
    end
  end

  describe "authorization" do
    it "does not allow access to other user's assets" do
      other_user = create(:user)
      other_asset = create(:asset, user: other_user)

      expect {
        get edit_asset_path(other_asset)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
