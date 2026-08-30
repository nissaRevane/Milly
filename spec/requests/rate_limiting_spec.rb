require "rails_helper"

# Les limites tiennent leurs compteurs dans Milly::RATE_LIMIT_STORE, un cache mémoire à
# part : Rails.cache est un :null_store en test, et compter dedans reviendrait à ne pas
# compter. On le vide entre les exemples, sinon le premier épuise le quota des suivants.
RSpec.describe "Rate limiting", type: :request do
  before { Milly::RATE_LIMIT_STORE.clear }

  describe "sign in" do
    let(:user) { create(:user) }

    it "turns away an IP that keeps guessing passwords" do
      10.times do
        post user_session_path, params: { user: { email: user.email, password: "wrong-password" } }
      end
      expect(response).not_to redirect_to(new_user_session_path)

      post user_session_path, params: { user: { email: user.email, password: "wrong-password" } }

      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to eq(I18n.t("flash.errors.rate_limited"))
    end

    it "still lets a first, legitimate attempt through" do
      post user_session_path, params: { user: { email: user.email, password: user.password } }

      expect(flash[:alert]).to be_nil
    end
  end

  describe "password reset" do
    it "caps how many reset emails one IP can trigger" do
      5.times { post user_password_path, params: { user: { email: "someone@example.com" } } }

      expect {
        post user_password_path, params: { user: { email: "someone@example.com" } }
      }.not_to change { ActionMailer::Base.deliveries.size }

      expect(flash[:alert]).to eq(I18n.t("flash.errors.rate_limited"))
    end
  end

  describe "sign up" do
    it "caps how many accounts one IP can open per hour" do
      5.times do |n|
        post user_registration_path, params: { user: {
          firstname: "A", lastname: "B", email: "new#{n}@example.com",
          password: "motdepasse-solide", password_confirmation: "motdepasse-solide"
        } }
      end

      expect {
        post user_registration_path, params: { user: {
          firstname: "A", lastname: "B", email: "spam@example.com",
          password: "motdepasse-solide", password_confirmation: "motdepasse-solide"
        } }
      }.not_to change(User, :count)
    end
  end
end
