require "rails_helper"

RSpec.describe "Content Security Policy", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  # The importmap and the entry-point import are inline script tags, so the
  # policy has to nonce them or the browser drops every bit of JavaScript.
  it "nonces the inline importmap script tags with the nonce it advertises" do
    get assets_path

    nonce = response.headers["Content-Security-Policy"][/script-src[^;]*'nonce-([^']+)'/, 1]
    expect(nonce).to be_present

    expect(response.body).to include(%(<script type="importmap" data-turbo-track="reload" nonce="#{nonce}">))
    expect(response.body).to include(%(<script type="module" nonce="#{nonce}">))
  end
end
