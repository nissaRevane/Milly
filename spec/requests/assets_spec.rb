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

  describe "GET /assets/:id" do
    it "renders the fiche, whose facts are corrected in place" do
      asset = create(:asset, user: user, name: "Livret A", ownership_share: 60)

      get asset_path(asset)

      expect(response).to have_http_status(:success)
      doc = Nokogiri::HTML(response.body)

      # Le nom s'édite dans le titre, les autres faits dans la liste : chacun porte son
      # propre formulaire vers l'update, et aucun ne mène à une page de saisie séparée.
      expect(doc.at_css("h1 .inline-edit-trigger").text.strip).to eq("Livret A")
      forms = doc.css("form.inline-edit-form[action='#{asset_path(asset)}']")
      expect(forms.length).to be >= 6
      expect(doc.at_css("select#asset_asset_type")).not_to be_nil
      expect(doc.at_css("select#asset_risk_level")).not_to be_nil
      expect(doc.at_css("input#asset_ownership_share")).not_to be_nil
      expect(doc.at_css("input#asset_started_on")).not_to be_nil
      expect(doc.at_css("input#asset_ended_on")).not_to be_nil
      expect(response.body).to include("60 %")
    end

    # « Immobilier » n'est pas un type qu'on prend ni qu'on quitte : le select ne l'offre pas.
    it "offers every type but immobilier" do
      asset = create(:asset, user: user)

      get asset_path(asset)

      options = Nokogiri::HTML(response.body).css("select#asset_asset_type option").map(&:text)
      expect(options).not_to include("Immobilier")
      expect(options).to include("Compte épargne")
    end

    it "offers the fiche and the évolution" do
      asset = create(:asset, user: user)

      get asset_path(asset)

      tabs = Nokogiri::HTML(response.body).css(".tab-nav .tab-link")
      expect(tabs.map { |tab| tab.text.strip }).to eq(["Fiche", "Évolution"])
      expect(tabs.first["aria-current"]).to eq("page")
    end
  end

  describe "the évolution tab" do
    it "reads the asset's amounts bilan after bilan, with its two variations" do
      asset = create(:asset, user: user, name: "Livret A", ownership_share: 50)
      [[Date.new(2024, 6, 30), 10_000], [Date.new(2025, 6, 30), 12_000],
       [Date.new(2025, 12, 31), 14_000]].each do |date, value|
        create(:balance_sheet_asset,
               balance_sheet: create(:balance_sheet, user: user, closing_date: date),
               asset: asset, value: value)
      end

      get asset_path(asset, tab: "history")

      expect(response).to have_http_status(:success)
      doc = Nokogiri::HTML(response.body)

      # Le montant lu est la valeur DÉTENUE, quote-part appliquée, comme sur le bilan.
      expect(doc.at_css(".stat-card-highlight .stat-value").text).to include("7 000")
      expect(doc.css(".stat-card .variation-gain").length).to eq(2)
      expect(doc.css(".chart-line .chart-point").length).to eq(3)
    end

    it "says so when no bilan carries the asset yet" do
      asset = create(:asset, user: user)

      get asset_path(asset, tab: "history")

      expect(Nokogiri::HTML(response.body).at_css(".empty-state").text)
        .to include("Cet actif ne figure dans aucun bilan")
    end

    # Un onglet inconnu ne casse rien : la fiche répond.
    it "falls back to the fiche when the tab is unknown" do
      asset = create(:asset, user: user)

      get asset_path(asset, tab: "bogus")

      expect(response).to have_http_status(:success)
      expect(Nokogiri::HTML(response.body).at_css(".tab-link-active").text.strip).to eq("Fiche")
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

    it "creates an asset with its lifespan" do
      post assets_path, params: { asset: { name: "Livret A", risk_level: "low", asset_type: "savings_account",
                                          started_on: "2020-01-05", ended_on: "2023-09-30" } }

      asset = Asset.last
      expect(asset.started_on).to eq(Date.new(2020, 1, 5))
      expect(asset.ended_on).to eq(Date.new(2023, 9, 30))
    end

    it "does not create with a lifespan ending before it starts" do
      expect {
        post assets_path, params: { asset: { name: "Livret A", risk_level: "low", asset_type: "savings_account",
                                            started_on: "2020-06-01", ended_on: "2020-05-31" } }
      }.not_to change(Asset, :count)

      expect(response).to have_http_status(:unprocessable_entity)
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

    it "reads its name, type and bien rather than offering them for editing" do
      get asset_path(asset)

      doc = Nokogiri::HTML(response.body)
      # Le nom vient du bien : le titre n'a pas de déclencheur d'édition, et rien ne le poste.
      expect(doc.css("h1 .inline-edit-trigger")).to be_empty
      expect(doc.css("input#asset_name")).to be_empty
      expect(doc.css("select#asset_asset_type")).to be_empty
      expect(doc.css("select#asset_property_id")).to be_empty
      expect(response.body).to include("Le nom de cet actif est celui du bien immobilier")
      expect(response.body).to include("Maison")
      # Ce qui reste modifiable l'est sur place.
      expect(doc.at_css("input#asset_ownership_share")).not_to be_nil
      expect(doc.at_css("select#asset_risk_level")).not_to be_nil
      expect(doc.at_css("input#asset_started_on")).not_to be_nil
    end

    it "updates its risk level and ownership share" do
      patch asset_path(asset), params: { asset: { risk_level: "high", ownership_share: "50" } }

      expect(asset.reload.risk_level).to eq("high")
      expect(asset.ownership_share).to eq(50)
      expect(response).to redirect_to(asset_path(asset))
    end

    # La période du bien n'est qu'un défaut : elle reste modifiable sur la fiche de l'actif.
    it "updates its lifespan" do
      patch asset_path(asset), params: { asset: { started_on: "2019-03-04", ended_on: "2025-02-28" } }

      asset.reload
      expect(asset.started_on).to eq(Date.new(2019, 3, 4))
      expect(asset.ended_on).to eq(Date.new(2025, 2, 28))
      expect(response).to redirect_to(asset_path(asset))
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
      expect(response).to redirect_to(asset_path(asset))
    end

    it "carries no delete button, as it is deleted with its bien" do
      asset

      get assets_path

      doc = Nokogiri::HTML(response.body)
      expect(doc.css("form[action='#{asset_path(asset)}']")).to be_empty
      expect(doc.css("a[href='#{asset_path(asset)}']")).to be_present
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

  # Le rattachement à un bien ne se saisit plus ici : seul l'actif immobilier se rattache à
  # un bien, et c'est le bien qui le crée et qui le rattache (voir PropertyLinkable).
  describe "linking an asset to a property" do
    it "offers no property select, even to a user who has biens" do
      create(:property, user: user, name: "Maison", usage: :primary_residence)

      get new_asset_path

      doc = Nokogiri::HTML(response.body)
      expect(doc.css("select#asset_property_id")).to be_empty
      expect(response.body).not_to include("Bien immobilier rattaché")
    end

    it "ignores a submitted property on a new asset" do
      property = create(:property, user: user)

      post assets_path, params: {
        asset: { name: "Travaux", risk_level: "low", asset_type: "receivable", property_id: property.id }
      }

      expect(response).to redirect_to(assets_path)
      expect(Asset.find_by(name: "Travaux").property_id).to be_nil
    end

    it "ignores a submitted property on an existing asset" do
      asset = create(:asset, user: user)
      property = create(:property, user: user)

      patch asset_path(asset), params: { asset: { property_id: property.id } }

      expect(response).to redirect_to(asset_path(asset))
      expect(asset.reload.property_id).to be_nil
    end

    # A forged property_id would otherwise satisfy the foreign key and leak the other
    # account's bien (name and usage) onto this user's balance sheet.
    it "refuses to link an asset to another user's property" do
      foreign = create(:property, user: create(:user), name: "Villa du voisin")

      post assets_path, params: {
        asset: { name: "Maison", risk_level: "low", asset_type: "savings_account", property_id: foreign.id }
      }

      created = user.assets.sole
      expect(created.property_id).to be_nil
      expect(foreign.reload.assets).not_to include(created)
    end
  end

  describe "PATCH /assets/:id" do
    let(:asset) { create(:asset, user: user, name: "Old Name") }

    # La fiche est le formulaire : on revient dessus plutôt que sur la liste — on corrige un
    # champ pour continuer à lire l'actif, pas pour le quitter.
    it "updates the asset and comes back to the fiche" do
      patch asset_path(asset), params: { asset: { name: "New Name" } }
      expect(asset.reload.name).to eq("New Name")
      expect(response).to redirect_to(asset_path(asset))
    end

    it "renders the fiche again with its errors when the update is refused" do
      patch asset_path(asset), params: { asset: { name: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(asset.reload.name).to eq("Old Name")
      expect(Nokogiri::HTML(response.body).at_css(".alert-danger").text)
        .to include("doit être rempli")
      expect(response.body).to include("tab-nav")
    end

    it "updates the asset type" do
      patch asset_path(asset), params: { asset: { asset_type: "financial_investment" } }
      expect(asset.reload.asset_type).to eq("financial_investment")
      expect(response).to redirect_to(asset_path(asset))
    end

    it "updates the ownership share" do
      patch asset_path(asset), params: { asset: { ownership_share: "33.33" } }
      expect(asset.reload.ownership_share).to eq(BigDecimal("33.33"))
      expect(response).to redirect_to(asset_path(asset))
    end

    it "updates the lifespan" do
      patch asset_path(asset), params: { asset: { started_on: "2020-01-05", ended_on: "2023-09-30" } }

      asset.reload
      expect(asset.started_on).to eq(Date.new(2020, 1, 5))
      expect(asset.ended_on).to eq(Date.new(2023, 9, 30))
      expect(response).to redirect_to(asset_path(asset))
    end

    it "clears a lifespan bound submitted empty" do
      asset.update!(ended_on: Date.new(2023, 9, 30))

      patch asset_path(asset), params: { asset: { ended_on: "" } }

      expect(asset.reload.ended_on).to be_nil
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

      get asset_path(other_asset)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("flash.errors.not_found"))
      expect(response.body).not_to include("Villa du voisin")
    end
  end
end
