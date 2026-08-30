require "rails_helper"

# Le compte est la frontière. Ces exemples ne vérifient pas une règle métier mais une
# limite : tant que l'inscription est ouverte, n'importe qui peut se créer un compte et
# forger des identifiants dans un formulaire. Chaque clé étrangère qui traverse les
# paramètres a donc son exemple ici.
RSpec.describe "Account isolation", type: :request do
  let(:victim) { create(:user) }
  let(:attacker) { create(:user) }

  before { sign_in attacker }

  describe "balance sheet asset lines" do
    let(:sheet) { create(:balance_sheet, user: attacker) }
    let!(:foreign_asset) { create(:asset, user: victim, name: "Compte Suisse UBS") }

    it "refuses an asset_id belonging to another account" do
      expect {
        post balance_sheet_balance_sheet_assets_path(sheet),
             params: { balance_sheet_asset: { asset_id: foreign_asset.id, value: 250_000 } }
      }.not_to change(BalanceSheetAsset, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "never renders the other account's asset name" do
      post balance_sheet_balance_sheet_assets_path(sheet),
           params: { balance_sheet_asset: { asset_id: foreign_asset.id, value: 250_000 } }

      expect(response.body).not_to include("Compte Suisse UBS")
    end

    it "refuses to repoint an existing line at another account's asset" do
      own_asset = create(:asset, user: attacker)
      line = create(:balance_sheet_asset, balance_sheet: sheet, asset: own_asset)

      patch balance_sheet_balance_sheet_asset_path(sheet, line),
            params: { balance_sheet_asset: { asset_id: foreign_asset.id, value: 1 } }

      expect(line.reload.asset_id).to eq(own_asset.id)
    end
  end

  describe "balance sheet liability lines" do
    let(:sheet) { create(:balance_sheet, user: attacker) }
    let!(:foreign_liability) { create(:liability, user: victim, name: "Prêt Banque Privée") }

    it "refuses a liability_id belonging to another account" do
      expect {
        post balance_sheet_balance_sheet_liabilities_path(sheet),
             params: { balance_sheet_liability: { liability_id: foreign_liability.id, remaining_capital: 90_000 } }
      }.not_to change(BalanceSheetLiability, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "never renders the other account's liability name" do
      post balance_sheet_balance_sheet_liabilities_path(sheet),
           params: { balance_sheet_liability: { liability_id: foreign_liability.id, remaining_capital: 90_000 } }

      expect(response.body).not_to include("Prêt Banque Privée")
    end
  end
end
