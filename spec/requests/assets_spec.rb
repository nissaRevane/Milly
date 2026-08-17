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
          asset: { name: "Maison", risk_level: "low", asset_type: "savings_account", ownership_share: "60" }
        }
      }.to change(Asset, :count).by(1)

      expect(Asset.last.ownership_share).to eq(60.0)
      expect(response).to redirect_to(assets_path)
    end

    it "does not create with an ownership share above 100" do
      expect {
        post assets_path, params: {
          asset: { name: "Maison", risk_level: "low", asset_type: "savings_account", ownership_share: "150" }
        }
      }.not_to change(Asset, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "the immobilier type" do
    it "is not offered by the form" do
      get new_asset_path

      doc = Nokogiri::HTML(response.body)
      options = doc.css("select#asset_asset_type option").map { |option| option.text.strip }

      expect(options).to eq(["Cash", "Compte courant", "Compte épargne", "Placement financier", "Créance"])
      expect(options).not_to include("Immobilier")
    end

    it "is still offered by the index filter, where such lines have to be findable" do
      create(:asset, user: user)

      get assets_path

      doc = Nokogiri::HTML(response.body)
      expect(doc.css("select#asset_type option").map { |option| option.text.strip }).to include("Immobilier")
    end

    it "refuses a submitted immobilier type instead of saving another one" do
      expect {
        post assets_path, params: { asset: { name: "Maison", risk_level: "low", asset_type: "real_estate" } }
      }.not_to change(Asset, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("que pour l&#39;actif créé avec un bien immobilier")
    end

    it "refuses to link a forged immobilier asset to a bien" do
      property = create(:property, user: user)

      expect {
        post assets_path, params: {
          asset: { name: "Autre", risk_level: "low", asset_type: "real_estate", property_id: property.id }
        }
      }.not_to change(Asset, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuses to turn an existing asset into an immobilier one" do
      asset = create(:asset, user: user, asset_type: "savings_account")

      patch asset_path(asset), params: { asset: { asset_type: "real_estate" } }

      expect(asset.reload.asset_type).to eq("savings_account")
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "the asset of a bien" do
    let(:property) { create(:property, user: user, name: "Maison") }
    let(:asset) { property.real_estate_asset }

    it "shows its name and type as read-only, and offers no bien select" do
      get edit_asset_path(asset)

      doc = Nokogiri::HTML(response.body)
      expect(doc.css("input#asset_name").first["disabled"]).to eq("disabled")
      expect(doc.css("select#asset_asset_type")).to be_empty
      expect(doc.css("select#asset_property_id")).to be_empty
      expect(response.body).to include("Le nom de cet actif est celui du bien immobilier")
    end

    it "updates its risk level and ownership share" do
      patch asset_path(asset), params: { asset: { risk_level: "high", ownership_share: "50" } }

      expect(asset.reload.risk_level).to eq("high")
      expect(asset.ownership_share).to eq(50)
      expect(response).to redirect_to(assets_path)
    end

    it "ignores a submitted name, type and bien" do
      other = create(:property, user: user, name: "Studio")

      patch asset_path(asset), params: {
        asset: { name: "Renommé", asset_type: "savings_account", property_id: other.id }
      }

      asset.reload
      expect(asset.name).to eq("Maison")
      expect(asset.asset_type).to eq("real_estate")
      expect(asset.property).to eq(property)
      expect(response).to redirect_to(assets_path)
    end

    it "carries no delete button, as it is deleted with its bien" do
      asset

      get assets_path

      doc = Nokogiri::HTML(response.body)
      expect(doc.css("form[action='#{asset_path(asset)}']")).to be_empty
      expect(doc.css("a[href='#{edit_asset_path(asset)}']")).to be_present
    end

    it "cannot be deleted on its own" do
      asset

      expect {
        delete asset_path(asset)
      }.not_to change(Asset, :count)

      expect(response).to redirect_to(assets_path)
      expect(flash[:alert]).to eq(I18n.t("flash.assets.property_owned"))
    end

    # Deleting a bien unlinks its asset instead of deleting it, to keep the balance sheet
    # history; what is left is the user's to delete and to rename.
    it "can be deleted and renamed once its bien is gone" do
      asset
      property.destroy

      patch asset_path(asset), params: { asset: { name: "Ancienne maison" } }
      expect(asset.reload.name).to eq("Ancienne maison")

      expect {
        delete asset_path(asset)
      }.to change(Asset, :count).by(-1)
    end
  end

  describe "linking an asset to a property" do
    it "offers no property select when the user has no property" do
      get new_asset_path

      expect(response.body).not_to include("asset_property_id")
      expect(response.body).not_to include("Bien immobilier rattaché")
    end

    it "offers the user's properties ordered by usage then name" do
      create(:property, user: user, name: "Studio", usage: :rental)
      create(:property, user: user, name: "Maison", usage: :primary_residence)
      create(:property, user: create(:user), name: "Villa du voisin")

      get new_asset_path

      doc = Nokogiri::HTML(response.body)
      options = doc.css("select#asset_property_id option").map { |option| option.text.strip }

      expect(options).to eq(["Aucun bien", "Maison", "Studio"])
      expect(response.body).to include("Bien immobilier rattaché")
    end

    it "creates an asset linked to a property" do
      property = create(:property, user: user)

      post assets_path, params: {
        asset: { name: "Travaux", risk_level: "low", asset_type: "receivable", property_id: property.id }
      }

      expect(Asset.last.property).to eq(property)
      expect(response).to redirect_to(assets_path)
    end

    it "unlinks an asset when the blank option is submitted" do
      property = create(:property, user: user)
      asset = create(:asset, user: user, property: property)

      patch asset_path(asset), params: { asset: { property_id: "" } }

      expect(asset.reload.property_id).to be_nil
      expect(response).to redirect_to(assets_path)
    end

    # A forged property_id would otherwise satisfy the foreign key and leak the other
    # account's bien (name and usage) onto this user's balance sheet.
    it "refuses to link a new asset to another user's property" do
      foreign = create(:property, user: create(:user), name: "Villa du voisin")

      post assets_path, params: {
        asset: { name: "Maison", risk_level: "low", asset_type: "savings_account", property_id: foreign.id }
      }

      created = user.assets.sole
      expect(created.property_id).to be_nil
      expect(foreign.reload.assets).not_to include(created)
    end

    it "refuses to link an existing asset to another user's property" do
      asset = create(:asset, user: user)
      foreign = create(:property, user: create(:user), name: "Villa du voisin")

      patch asset_path(asset), params: { asset: { property_id: foreign.id } }

      expect(asset.reload.property_id).to be_nil
      expect(foreign.reload.assets).not_to include(asset)
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
      patch asset_path(asset), params: { asset: { asset_type: "financial_investment" } }
      expect(asset.reload.asset_type).to eq("financial_investment")
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
      other_asset = create(:asset, user: other_user, name: "Villa du voisin")

      get edit_asset_path(other_asset)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("flash.errors.not_found"))
      expect(response.body).not_to include("Villa du voisin")
    end
  end
end
