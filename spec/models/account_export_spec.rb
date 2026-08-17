require "rails_helper"

RSpec.describe AccountExport do
  let(:user) { create(:user, email: "quentin@example.com", firstname: "Quentin", lastname: "GIRARD") }

  describe "#to_h" do
    it "exports the account identity without the real password" do
      data = described_class.new(user).to_h

      expect(data["user"]).to include(
        "email" => "quentin@example.com",
        "firstname" => "Quentin",
        "lastname" => "GIRARD"
      )
      expect(data["user"]["password"]).to be_present
      expect(data["user"]["password"]).not_to eq("password123")
      expect(user.valid_password?(data["user"]["password"])).to be false
    end

    it "generates a different password on every export" do
      passwords = 2.times.map { described_class.new(user).to_h.dig("user", "password") }

      expect(passwords.uniq.size).to eq(2)
    end

    it "exports assets and liabilities in creation order" do
      create(:asset, user: user, name: "Liquidités", risk_level: :low, asset_type: :cash)
      create(:asset, user: user, name: "Immobilier", risk_level: :medium, asset_type: :real_estate, ownership_share: 50)
      create(:liability, user: user, name: "Dettes LT", risk_level: :low, liability_type: :real_estate_loan, ownership_share: 50)

      data = described_class.new(user).to_h

      expect(data["assets"]).to eq([
        { "name" => "Liquidités", "risk_level" => "low", "asset_type" => "cash", "ownership_share" => 100, "property" => nil },
        { "name" => "Immobilier", "risk_level" => "medium", "asset_type" => "real_estate", "ownership_share" => 50, "property" => nil }
      ])
      expect(data["liabilities"]).to eq([
        { "name" => "Dettes LT", "risk_level" => "low", "liability_type" => "real_estate_loan", "ownership_share" => 50, "property" => nil }
      ])
    end

    it "exports properties in creation order" do
      create(:property, user: user, name: "Maison", usage: :primary_residence)
      create(:property, user: user, name: "Studio", usage: :rental)

      data = described_class.new(user).to_h

      expect(data["properties"]).to eq([
        { "name" => "Maison", "usage" => "primary_residence" },
        { "name" => "Studio", "usage" => "rental" }
      ])
    end

    it "references the property of an asset and of a liability by name" do
      # The only asset here is the one created with the bien: it carries its name, and
      # db/seeds.rb matches it back on that name when the export is re-seeded.
      property = create(:property, user: user, name: "Maison")
      create(:liability, user: user, name: "Prêt maison", liability_type: :real_estate_loan, property: property)

      data = described_class.new(user).to_h

      expect(data["assets"].sole).to include(
        "name" => "Maison", "asset_type" => "real_estate", "property" => "Maison"
      )
      expect(data["liabilities"].sole["property"]).to eq("Maison")
    end

    it "exports balance sheets oldest first, keyed by line name" do
      asset = create(:asset, user: user, name: "Liquidités")
      liability = create(:liability, user: user, name: "Dettes LT")
      recent = create(:balance_sheet, user: user, closing_date: Date.new(2026, 3, 18))
      older = create(:balance_sheet, user: user, closing_date: Date.new(2021, 3, 18))
      create(:balance_sheet_asset, balance_sheet: older, asset: asset, value: 3140.23)
      create(:balance_sheet_liability, balance_sheet: recent, liability: liability, remaining_capital: 77000)

      data = described_class.new(user).to_h

      expect(data["balance_sheets"]).to eq([
        { "closing_date" => "2021-03-18", "assets" => { "Liquidités" => 3140.23 }, "liabilities" => {} },
        { "closing_date" => "2026-03-18", "assets" => {}, "liabilities" => { "Dettes LT" => 77000 } }
      ])
    end

    it "leaves out other accounts" do
      other = create(:user)
      create(:asset, user: other, name: "Pas à moi")
      create(:liability, user: other, name: "Pas à moi non plus")
      create(:balance_sheet, user: other, closing_date: Date.new(2026, 3, 18))

      data = described_class.new(user).to_h

      expect(data["assets"]).to be_empty
      expect(data["liabilities"]).to be_empty
      expect(data["balance_sheets"]).to be_empty
    end

    it "leaves out the properties of other accounts" do
      create(:property, user: create(:user), name: "Pas à moi")

      expect(described_class.new(user).to_h["properties"]).to be_empty
    end
  end

  describe "#to_json" do
    it "serializes amounts as JSON numbers, not strings" do
      asset = create(:asset, user: user, name: "Liquidités", ownership_share: 33.33)
      balance_sheet = create(:balance_sheet, user: user, closing_date: Date.new(2021, 3, 18))
      create(:balance_sheet_asset, balance_sheet: balance_sheet, asset: asset, value: 3140.23)

      json = described_class.new(user).to_json

      expect(json).to include('"ownership_share": 33.33')
      expect(json).to include('"Liquidités": 3140.23')
      expect(JSON.parse(json).dig("balance_sheets", 0, "assets", "Liquidités")).to eq(3140.23)
    end

    # The hand-written seed file predates properties, so the export is now a strict
    # superset of it: every key it already had is still there, in the same order, and
    # the only additions are the property keys that db/seeds.rb reads when present.
    it "matches the structure db/seeds.rb reads" do
      seed_data = JSON.parse(File.read(Rails.root.join("db", "seed_data.json")))
      create(:asset, user: user)
      create(:liability, user: user)
      create(:balance_sheet, user: user)
      data = described_class.new(user).to_h

      expect(data.keys & seed_data.keys).to eq(seed_data.keys)
      expect(data.keys - seed_data.keys).to eq(["properties"])
      expect(data["user"].keys).to match_array(seed_data["user"].keys)

      %w[assets liabilities].each do |collection|
        seed_keys = seed_data[collection].first.keys
        exported_keys = data[collection].first.keys

        expect(exported_keys & seed_keys).to eq(seed_keys)
        expect(exported_keys - seed_keys).to eq(["property"])
      end

      expect(data["balance_sheets"].first.keys).to eq(seed_data["balance_sheets"].first.keys)
    end
  end

  describe "#filename" do
    it "names the file after the account and the day" do
      expect(described_class.new(user).filename)
        .to eq("milly-export-quentin-example-com-#{Date.current.iso8601}.json")
    end
  end
end
