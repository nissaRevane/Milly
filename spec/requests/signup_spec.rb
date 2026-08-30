require "rails_helper"

# L'inscription est ouverte : c'est le premier écran que voit un inconnu, et le seul dont
# les messages d'erreur sont lus par quelqu'un qui ne connaît pas encore l'application.
# Un « Translation missing » y est un bug visible — la longueur minimale du mot de passe
# n'avait jamais déclenché la sienne tant qu'elle valait six caractères.
RSpec.describe "Sign up", type: :request do
  before { Milly::RATE_LIMIT_STORE.clear }

  def sign_up(overrides = {})
    post user_registration_path, params: { user: {
      firstname: "Jeanne", lastname: "Martin", email: "jeanne@example.com",
      password: "motdepasse-solide", password_confirmation: "motdepasse-solide"
    }.merge(overrides) }
  end

  it "opens an account" do
    expect { sign_up }.to change(User, :count).by(1)
  end

  it "refuses a password shorter than the minimum, in French" do
    expect { sign_up(password: "court123", password_confirmation: "court123") }.not_to change(User, :count)

    expect(response.body).not_to include("Translation missing")
    expect(response.body).to include("10 caractères minimum")
  end

  it "refuses a mistyped confirmation, in French" do
    expect { sign_up(password_confirmation: "autre-chose-encore") }.not_to change(User, :count)

    expect(response.body).not_to include("Translation missing")
  end

  it "refuses a blank name or a malformed email without falling back to English" do
    sign_up(firstname: "", email: "pas-un-email")

    expect(response.body).not_to include("Translation missing")
  end
end
