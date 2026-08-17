require "rails_helper"

RSpec.describe "Properties", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /properties" do
    it "returns success" do
      get properties_path
      expect(response).to have_http_status(:success)
    end

    it "orders properties by usage, then name" do
      create(:property, user: user, name: "Zeta", usage: :primary_residence)
      create(:property, user: user, name: "Aaa", usage: :primary_residence)
      create(:property, user: user, name: "Studio", usage: :rental)
      create(:property, user: user, name: "Chalet", usage: :secondary_residence)

      get properties_path

      positions = ["Aaa", "Zeta", "Studio", "Chalet"].map { |name| response.body.index(name) }
      expect(positions).to eq(positions.compact.sort)
    end

    it "renders the usage label" do
      create(:property, user: user, name: "Maison", usage: :rental)

      get properties_path

      expect(response.body).to include("Maison")
      expect(response.body).to include("Locatif")
    end

    it "does not list another user's properties" do
      create(:property, user: create(:user), name: "Villa du voisin")

      get properties_path

      expect(response.body).not_to include("Villa du voisin")
      expect(response.body).to include("Aucun bien immobilier enregistré.")
    end
  end

  describe "GET /properties/new" do
    it "returns success" do
      get new_property_path
      expect(response).to have_http_status(:success)
    end

    it "offers every usage" do
      get new_property_path

      expect(response.body).to include("Résidence principale")
      expect(response.body).to include("Locatif")
      expect(response.body).to include("Résidence secondaire")
    end
  end

  describe "POST /properties" do
    it "creates a new property" do
      expect {
        post properties_path, params: { property: { name: "Maison", usage: "primary_residence" } }
      }.to change(Property, :count).by(1)

      expect(Property.last.usage).to eq("primary_residence")
      expect(Property.last.user).to eq(user)
      expect(response).to redirect_to(properties_path)
    end

    it "does not create with an unknown usage" do
      expect {
        post properties_path, params: { property: { name: "Maison", usage: "bogus" } }
      }.not_to change(Property, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "does not create without a name" do
      expect {
        post properties_path, params: { property: { name: "", usage: "rental" } }
      }.not_to change(Property, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "creates the immobilier asset of the bien along with it" do
      expect {
        post properties_path, params: { property: { name: "Maison", usage: "rental" } }
      }.to change(Asset, :count).by(1)

      asset = Property.last.real_estate_asset
      expect(asset.name).to eq("Maison")
      expect(asset.asset_type).to eq("real_estate")
      expect(asset.user).to eq(user)
    end

    it "creates no asset when the bien itself is rejected" do
      expect {
        post properties_path, params: { property: { name: "", usage: "rental" } }
      }.not_to change(Asset, :count)
    end

    it "announces the asset on the form" do
      get new_property_path

      expect(response.body).to include("sera créé automatiquement")
    end
  end

  describe "GET /properties/:id/edit" do
    it "returns success" do
      property = create(:property, user: user, name: "Maison")

      get edit_property_path(property)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Maison")
    end
  end

  describe "PATCH /properties/:id" do
    let(:property) { create(:property, user: user, name: "Old Name", usage: :primary_residence) }

    it "updates the name" do
      patch property_path(property), params: { property: { name: "New Name" } }

      expect(property.reload.name).to eq("New Name")
      expect(response).to redirect_to(properties_path)
    end

    it "updates the usage" do
      patch property_path(property), params: { property: { usage: "rental" } }

      expect(property.reload.usage).to eq("rental")
      expect(response).to redirect_to(properties_path)
    end

    it "renames the immobilier asset of the bien along with it" do
      asset = property.real_estate_asset

      patch property_path(property), params: { property: { name: "New Name" } }

      expect(asset.reload.name).to eq("New Name")
    end

    it "leaves the asset name alone when only the usage changes" do
      asset = property.real_estate_asset

      patch property_path(property), params: { property: { usage: "rental" } }

      expect(asset.reload.name).to eq("Old Name")
    end

    it "does not update with a blank name" do
      patch property_path(property), params: { property: { name: "" } }

      expect(property.reload.name).to eq("Old Name")
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /properties/:id" do
    it "destroys the property" do
      property = create(:property, user: user)

      expect {
        delete property_path(property)
      }.to change(Property, :count).by(-1)

      expect(response).to redirect_to(properties_path)
    end

    it "keeps its own immobilier asset, unlinked, so the balance sheet history survives" do
      property = create(:property, user: user)
      asset = property.real_estate_asset

      expect {
        delete property_path(property)
      }.not_to change(Asset, :count)

      expect(asset.reload.property_id).to be_nil
      expect(asset.asset_type).to eq("real_estate")
    end

    it "keeps the linked asset and only unlinks it" do
      property = create(:property, user: user)
      asset = create(:asset, user: user, property: property)

      expect {
        delete property_path(property)
      }.not_to change(Asset, :count)

      expect(asset.reload.property_id).to be_nil
    end
  end

  describe "authorization" do
    it "does not allow access to another user's property" do
      other_property = create(:property, user: create(:user), name: "Villa du voisin")

      get edit_property_path(other_property)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("flash.errors.not_found"))
      expect(response.body).not_to include("Villa du voisin")
    end

    it "does not let a user destroy another user's property" do
      other_property = create(:property, user: create(:user))

      expect {
        delete property_path(other_property)
      }.not_to change(Property, :count)

      expect(response).to redirect_to(root_path)
    end
  end

  describe "authentication" do
    it "redirects unauthenticated users" do
      sign_out user
      get properties_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
