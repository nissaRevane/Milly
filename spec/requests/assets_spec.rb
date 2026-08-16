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

    it "colors the asset type badge with the risk level" do
      create(:asset, user: user, name: "Maison", asset_type: :real_estate, risk_level: :high)

      get assets_path

      expect(response.body).to include('<span class="badge badge-danger" title="Élevé">')
      expect(response.body).to include("Immobilier")
    end

    it "renders the ownership share" do
      create(:asset, user: user, name: "Maison", ownership_share: 60)

      get assets_path

      expect(response.body).to include("60 %")
    end

    it "filters the assets by type" do
      create(:asset, user: user, name: "Maison", asset_type: :real_estate)
      create(:asset, user: user, name: "Livret A", asset_type: :savings_account)

      get assets_path, params: { asset_type: "real_estate" }

      expect(response.body).to include("Maison")
      expect(response.body).not_to include("Livret A")
    end

    it "wires the filter to auto-submit without an inline handler" do
      create(:asset, user: user)

      get assets_path

      expect(response.body).to include('data-controller="auto-submit"')
      expect(response.body).to include('data-action="change-&gt;auto-submit#submit"')
      expect(response.body).not_to include("onchange=")
    end

    it "ignores an unknown type filter" do
      create(:asset, user: user, name: "Maison", asset_type: :real_estate)
      create(:asset, user: user, name: "Livret A", asset_type: :savings_account)

      get assets_path, params: { asset_type: "not_a_type" }

      expect(response.body).to include("Maison")
      expect(response.body).to include("Livret A")
    end

    it "shows a filtered empty state when no asset matches the type" do
      create(:asset, user: user, name: "Livret A", asset_type: :savings_account)

      get assets_path, params: { asset_type: "real_estate" }

      expect(response.body).to include("Aucun actif pour ce type.")
      expect(response.body).to include("Filtrer par type")
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

    it "does not create with an unknown asset type" do
      expect {
        post assets_path, params: { asset: { name: "X", risk_level: "low", asset_type: "bogus" } }
      }.not_to change(Asset, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "does not create with invalid params" do
      expect {
        post assets_path, params: { asset: { name: "", risk_level: "low" } }
      }.not_to change(Asset, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "creates an asset with the submitted ownership share" do
      expect {
        post assets_path, params: {
          asset: { name: "Maison", risk_level: "low", asset_type: "real_estate", ownership_share: "60" }
        }
      }.to change(Asset, :count).by(1)

      expect(Asset.last.ownership_share).to eq(60.0)
      expect(response).to redirect_to(assets_path)
    end

    it "does not create with an ownership share above 100" do
      expect {
        post assets_path, params: {
          asset: { name: "Maison", risk_level: "low", asset_type: "real_estate", ownership_share: "150" }
        }
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

    it "updates the ownership share" do
      patch asset_path(asset), params: { asset: { ownership_share: "33.33" } }
      expect(asset.reload.ownership_share).to eq(BigDecimal("33.33"))
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
