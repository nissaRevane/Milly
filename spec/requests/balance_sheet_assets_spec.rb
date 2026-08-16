require "rails_helper"

RSpec.describe "BalanceSheetAssets", type: :request do
  let(:user) { create(:user) }
  let(:balance_sheet) { create(:balance_sheet, user: user) }
  let!(:used_asset) { create(:asset, user: user, name: "Livret A") }
  let!(:free_asset) { create(:asset, user: user, name: "PEA") }

  before do
    sign_in user
    create(:balance_sheet_asset, balance_sheet: balance_sheet, asset: used_asset)
  end

  describe "GET /balance_sheets/:id/balance_sheet_assets/new" do
    it "returns success" do
      get new_balance_sheet_balance_sheet_asset_path(balance_sheet)
      expect(response).to have_http_status(:success)
    end

    it "excludes assets already present in the balance sheet from the dropdown" do
      get new_balance_sheet_balance_sheet_asset_path(balance_sheet)

      expect(response.body).not_to include("value=\"#{used_asset.id}\"")
      expect(response.body).to include("value=\"#{free_asset.id}\"")
    end

    it "excludes assets belonging to another user" do
      other_asset = create(:asset, user: create(:user), name: "Autre")

      get new_balance_sheet_balance_sheet_asset_path(balance_sheet)

      expect(response.body).not_to include("value=\"#{other_asset.id}\"")
    end
  end

  describe "GET /balance_sheets/:id/balance_sheet_assets/:id/edit" do
    it "keeps the currently selected asset in the dropdown" do
      balance_sheet_asset = balance_sheet.balance_sheet_assets.first

      get edit_balance_sheet_balance_sheet_asset_path(balance_sheet, balance_sheet_asset)

      expect(response.body).to include("value=\"#{used_asset.id}\"")
      expect(response.body).to include("value=\"#{free_asset.id}\"")
    end
  end

  describe "POST /balance_sheets/:id/balance_sheet_assets" do
    it "creates the line for an available asset" do
      expect {
        post balance_sheet_balance_sheet_assets_path(balance_sheet),
             params: { balance_sheet_asset: { asset_id: free_asset.id, value: 5_000 } }
      }.to change(BalanceSheetAsset, :count).by(1)

      expect(response).to redirect_to(balance_sheet)
    end

    it "rejects an asset already present in the balance sheet" do
      expect {
        post balance_sheet_balance_sheet_assets_path(balance_sheet),
             params: { balance_sheet_asset: { asset_id: used_asset.id, value: 5_000 } }
      }.not_to change(BalanceSheetAsset, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
