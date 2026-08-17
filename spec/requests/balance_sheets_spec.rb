require "rails_helper"

RSpec.describe "BalanceSheets", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def currency(amount)
    ActionController::Base.helpers.number_to_currency(amount)
  end

  describe "GET /balance_sheets" do
    it "returns success" do
      get balance_sheets_path
      expect(response).to have_http_status(:success)
    end

    it "groups balance sheets by year in an accordion" do
      create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31))
      create(:balance_sheet, user: user, closing_date: Date.new(2025, 6, 30))
      create(:balance_sheet, user: user, closing_date: Date.new(2024, 12, 31))

      get balance_sheets_path

      doc = Nokogiri::HTML(response.body)
      items = doc.css(".balance-sheets-accordion .accordion-item")

      expect(items.map { |item| item.at_css(".accordion-year")&.text&.strip }).to eq(["2025", "2024"])
      expect(items.first["open"]).not_to be_nil
      expect(items.drop(1).map { |item| item["open"] }).to all(be_nil)
      expect(items.first.at_css(".badge")&.text&.strip).to eq("2")
    end
  end

  describe "GET /balance_sheets/:id" do
    it "returns success" do
      bs = create(:balance_sheet, user: user)
      get balance_sheet_path(bs)
      expect(response).to have_http_status(:success)
    end

    it "renders both the full and the owned amount for a partially owned line" do
      bs = create(:balance_sheet, user: user)
      half = create(:asset, user: user, name: "Maison", asset_type: :real_estate, ownership_share: 50)
      quarter = create(:asset, user: user, name: "Terrain", asset_type: :real_estate, ownership_share: 25)
      create(:balance_sheet_asset, balance_sheet: bs, asset: half, value: 200_000)
      create(:balance_sheet_asset, balance_sheet: bs, asset: quarter, value: 80_000)

      get balance_sheet_path(bs)

      expect(response).to have_http_status(:success)
      # Full values
      expect(response.body).to include(currency(200_000))
      expect(response.body).to include(currency(80_000))
      # Per-line owned values, none of which equals the 120 000 total
      expect(response.body).to include(currency(100_000))
      expect(response.body).to include(currency(20_000))
      expect(bs.total_assets).to eq(120_000)
      expect(response.body).to include(currency(120_000))
      # Share column
      expect(response.body).to include("50 %")
      expect(response.body).to include("25 %")
    end
  end

  describe "POST /balance_sheets" do
    it "creates a new balance sheet" do
      expect {
        post balance_sheets_path, params: { balance_sheet: { closing_date: "2025-12-31" } }
      }.to change(BalanceSheet, :count).by(1)
    end
  end

  describe "duplicating a balance sheet" do
    let(:asset) { create(:asset, user: user, name: "Livret A") }
    let(:liability) { create(:liability, user: user, name: "Prêt") }
    let!(:source) do
      create(:balance_sheet, user: user, closing_date: Date.new(2025, 12, 31)).tap do |bs|
        create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 12_000)
        create(:balance_sheet_liability, balance_sheet: bs, liability: liability, remaining_capital: 90_000)
      end
    end

    it "offers a duplicate link for each balance sheet on the index" do
      get balance_sheets_path

      doc = Nokogiri::HTML(response.body)
      expect(doc.css("a[href='#{new_balance_sheet_path(source_id: source.id)}']")).not_to be_empty
    end

    it "prefills the form and carries the source" do
      get new_balance_sheet_path(source_id: source.id)

      expect(response).to have_http_status(:success)
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("input[name='source_id']")["value"]).to eq(source.id.to_s)
    end

    it "copies every asset and liability line onto the new balance sheet" do
      expect {
        post balance_sheets_path, params: { balance_sheet: { closing_date: "2026-06-30" }, source_id: source.id }
      }.to change(BalanceSheet, :count).by(1)

      copy = BalanceSheet.order(:created_at).last
      expect(response).to redirect_to(copy)
      expect(copy.closing_date).to eq(Date.new(2026, 6, 30))
      expect(copy.balance_sheet_assets.pluck(:asset_id, :value)).to eq([[asset.id, 12_000]])
      expect(copy.balance_sheet_liabilities.pluck(:liability_id, :remaining_capital)).to eq([[liability.id, 90_000]])
      expect(source.reload.balance_sheet_assets.count).to eq(1)
    end

    it "does not copy anything when the closing date is already taken" do
      expect {
        post balance_sheets_path, params: { balance_sheet: { closing_date: "2025-12-31" }, source_id: source.id }
      }.not_to change(BalanceSheetAsset, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "does not let a user duplicate someone else's balance sheet" do
      other = create(:balance_sheet, user: create(:user))

      expect {
        get new_balance_sheet_path(source_id: other.id)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "GET /balance_sheets/:id/summary" do
    it "returns success" do
      bs = create(:balance_sheet, user: user)
      get summary_balance_sheet_path(bs)
      expect(response).to have_http_status(:success)
    end

    it "omits the risk breakdown headings when the balance sheet is empty" do
      bs = create(:balance_sheet, user: user)

      get summary_balance_sheet_path(bs)

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("Répartition par risque")
    end

    it "groups assets and liabilities by type" do
      bs = create(:balance_sheet, user: user)
      cash = create(:asset, user: user, name: "Espèces", asset_type: :cash, risk_level: :low)
      immo = create(:asset, user: user, name: "Maison", asset_type: :real_estate, risk_level: :medium)
      debt = create(:liability, user: user, name: "Prêt", risk_level: :low, liability_type: :real_estate_loan)
      create(:balance_sheet_asset, balance_sheet: bs, asset: cash, value: 1_000)
      create(:balance_sheet_asset, balance_sheet: bs, asset: immo, value: 200_000)
      create(:balance_sheet_liability, balance_sheet: bs, liability: debt, remaining_capital: 150_000)

      get summary_balance_sheet_path(bs)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Cash")
      expect(response.body).to include("Immobilier")
      expect(response.body).to include("Prêt")
      expect(response.body).to include("Crédit immobilier")
      expect(response.body).to include("Répartition par risque")
    end

    it "collapses each category behind its total amount" do
      bs = create(:balance_sheet, user: user)
      livret = create(:asset, user: user, name: "Livret A", asset_type: :cash)
      compte = create(:asset, user: user, name: "Compte courant", asset_type: :cash)
      create(:balance_sheet_asset, balance_sheet: bs, asset: livret, value: 1_000)
      create(:balance_sheet_asset, balance_sheet: bs, asset: compte, value: 500)

      get summary_balance_sheet_path(bs)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("summary-category-amount")
      expect(response.body).to include(currency(1_500))
      expect(response.body).not_to include("Sous-total")
      expect(response.body).not_to match(/<details class="summary-category" open/)
    end

    it "renders the owned amount for a partially owned asset" do
      bs = create(:balance_sheet, user: user)
      asset = create(:asset, user: user, name: "Maison", asset_type: :real_estate, ownership_share: 50)
      create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 200_000)

      get summary_balance_sheet_path(bs)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(currency(100_000))
      expect(response.body).not_to include(currency(200_000))
    end
  end

  describe "authentication" do
    it "redirects unauthenticated users" do
      sign_out user
      get balance_sheets_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
