require "rails_helper"

RSpec.describe "Exports", type: :request do
  let(:user) { create(:user) }

  describe "GET /export" do
    it "requires an authenticated user" do
      get export_path

      expect(response).to redirect_to(new_user_session_path)
    end

    context "when signed in" do
      before { sign_in user }

      it "sends the account as a JSON download" do
        get export_path

        expect(response).to have_http_status(:success)
        expect(response.media_type).to eq("application/json")
        expect(response.headers["Content-Disposition"]).to include("attachment")
        expect(response.headers["Content-Disposition"]).to include("milly-export-")
      end

      it "returns the account data with a substitute password" do
        asset = create(:asset, user: user, name: "Liquidités")
        balance_sheet = create(:balance_sheet, user: user, closing_date: Date.new(2021, 3, 18))
        create(:balance_sheet_asset, balance_sheet: balance_sheet, asset: asset, value: 3140.23)

        get export_path

        data = JSON.parse(response.body)
        expect(data["user"]["email"]).to eq(user.email)
        expect(data["user"]["password"]).not_to eq("password123")
        expect(data["assets"].first["name"]).to eq("Liquidités")
        expect(data["balance_sheets"].first["assets"]).to eq("Liquidités" => 3140.23)
      end

      it "never exposes the encrypted password" do
        get export_path

        expect(response.body).not_to include(user.encrypted_password)
        expect(response.body).not_to include("encrypted_password")
      end
    end
  end

  describe "the account page" do
    it "offers the export link to signed-in users" do
      sign_in user

      get account_path

      expect(response.body).to include(export_path)
      expect(response.body).to include("Exporter mes données")
    end
  end
end
