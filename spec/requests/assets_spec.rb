require "rails_helper"

RSpec.describe "Assets", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /assets" do
    it "returns success" do
      get assets_path
      expect(response).to have_http_status(:success)
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
        post assets_path, params: { asset: { name: "Livret A", risk_level: "low" } }
      }.to change(Asset, :count).by(1)

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
