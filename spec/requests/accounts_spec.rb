require "rails_helper"

RSpec.describe "Account", type: :request do
  let(:user) { create(:user) }

  describe "GET /mon-compte" do
    it "requires an authenticated user" do
      get account_path

      expect(response).to redirect_to(new_user_session_path)
    end

    context "when signed in" do
      before { sign_in user }

      it "shows the account identity" do
        get account_path

        expect(response).to have_http_status(:success)
        expect(response.body).to include(user.full_name)
        expect(response.body).to include(user.email)
      end

      it "offers the export as an action of the page" do
        get account_path

        expect(response.body).to include(export_path)
        expect(response.body).to include("Exporter mes données")
      end
    end
  end

  describe "PUT /users" do
    before { sign_in user }

    def change_password(current_password:, password: "nouveau-mot-de-passe")
      put user_registration_path, params: {
        user: {
          current_password: current_password,
          password: password,
          password_confirmation: password
        }
      }
    end

    it "changes the password and returns to the account page" do
      change_password(current_password: "password123")

      expect(response).to redirect_to(account_path)
      expect(user.reload.valid_password?("nouveau-mot-de-passe")).to be true
    end

    it "keeps the user signed in" do
      change_password(current_password: "password123")

      get account_path

      expect(response).to have_http_status(:success)
    end

    it "rejects a wrong current password" do
      change_password(current_password: "mauvais")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.reload.valid_password?("password123")).to be true
    end

    it "rejects a confirmation that does not match" do
      put user_registration_path, params: {
        user: {
          current_password: "password123",
          password: "nouveau-mot-de-passe",
          password_confirmation: "autre-mot-de-passe"
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.reload.valid_password?("password123")).to be true
    end
  end

  describe "the navbar" do
    it "links to the account page rather than listing the export" do
      sign_in user

      get balance_sheets_path

      expect(response.body).to include(account_path)
      expect(response.body).not_to include(">Exporter")
    end
  end
end
