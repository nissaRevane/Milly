require "rails_helper"

RSpec.describe Property, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:assets).dependent(:nullify) }
    it { is_expected.to have_many(:liabilities).dependent(:nullify) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }

    # The name is the identity of a bien in an export: AccountExport writes it and
    # db/seeds.rb resolves it back, first match wins, so a duplicate would silently
    # merge two biens into one on a round trip.
    it "rejects a second property with the same name for the same user" do
      first = create(:property, name: "Maison", usage: :primary_residence)
      duplicate = build(:property, user: first.user, name: "Maison", usage: :rental)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to eq(["est déjà utilisé pour un autre bien"])
    end

    it "lets two users each own a property with the same name" do
      create(:property, name: "Maison")

      expect(build(:property, name: "Maison")).to be_valid
    end

    it "is invalid with an unknown usage" do
      property = build(:property)
      property.usage = "bogus"
      expect(property).not_to be_valid
      expect(property.errors[:usage]).to be_present
    end

    it "is invalid without an usage" do
      property = build(:property, usage: nil)
      expect(property).not_to be_valid
      expect(property.errors[:usage]).to be_present
    end

    # The four descriptive fields are optional: every bien created before they existed
    # has none, and a bien is usable on the balance sheet without them.
    it "is valid without an address, a purchase price or an acquisition date" do
      expect(build(:property, address: nil, purchase_price: nil, acquired_on: nil, sold_on: nil)).to be_valid
    end

    it "is valid with a sale date on or after the acquisition date" do
      expect(build(:property, acquired_on: Date.new(2020, 1, 1), sold_on: Date.new(2020, 1, 1))).to be_valid
      expect(build(:property, acquired_on: Date.new(2020, 1, 1), sold_on: Date.new(2024, 6, 30))).to be_valid
    end

    it "is valid with a sale date and no acquisition date" do
      expect(build(:property, acquired_on: nil, sold_on: Date.new(2020, 1, 1))).to be_valid
    end

    it "rejects a sale date before the acquisition date" do
      property = build(:property, acquired_on: Date.new(2020, 1, 1), sold_on: Date.new(2019, 12, 31))

      expect(property).not_to be_valid
      expect(property.errors[:sold_on]).to eq(["ne peut pas précéder la date d'acquisition"])
    end

    it "is invalid with a negative purchase price" do
      property = build(:property, purchase_price: -1)

      expect(property).not_to be_valid
      expect(property.errors[:purchase_price]).to be_present
    end
  end

  describe "enums" do
    it {
      is_expected.to define_enum_for(:usage).with_values(
        primary_residence: 0, rental: 1, secondary_residence: 2
      ).validating
    }
  end

  describe "#usage_label" do
    it "delegates to the shared enum labels" do
      allow(EnumLabel).to receive(:for).with("property_usages", "rental").and_return("Locatif")

      expect(build(:property, usage: :rental).usage_label).to eq("Locatif")
    end
  end

  describe "the immobilier asset of the bien" do
    it "is created with the bien, named after it" do
      property = nil

      expect { property = create(:property, name: "Maison") }.to change(Asset, :count).by(1)

      asset = property.real_estate_asset
      expect(asset.name).to eq("Maison")
      expect(asset.asset_type).to eq("real_estate")
      expect(asset.user).to eq(property.user)
      expect(asset.ownership_share).to eq(100)
    end

    it "starts at a medium risk level rather than the column default" do
      asset = create(:property, name: "Maison").real_estate_asset

      expect(asset.risk_level).to eq("medium")
    end

    it "keeps the risk level an import or a seed carries" do
      property = create(:property, name: "Maison")

      property.real_estate_asset.update!(risk_level: :high)

      expect(property.reload.real_estate_asset.risk_level).to eq("high")
    end

    it "is not created when the bien is invalid" do
      user = create(:user)
      create(:property, user: user, name: "Maison")

      expect { build(:property, user: user, name: "Maison").save }.not_to change(Asset, :count)
    end

    it "is renamed with the bien" do
      property = create(:property, name: "Maison")
      asset = property.real_estate_asset

      property.update!(name: "Maison de famille")

      expect(asset.reload.name).to eq("Maison de famille")
    end

    it "is left alone when the bien changes anything but its name" do
      property = create(:property, name: "Maison", usage: :primary_residence)
      asset = property.real_estate_asset

      expect { property.update!(usage: :rental) }.not_to change { asset.reload.updated_at }
    end
  end

  describe "when destroyed" do
    it "unlinks its assets and liabilities instead of deleting them" do
      property = create(:property)
      asset = create(:asset, user: property.user, property: property, asset_type: :real_estate)
      liability = create(:liability, user: property.user, property: property, liability_type: :real_estate_loan)

      property.destroy

      expect(Asset.exists?(asset.id)).to be true
      expect(Liability.exists?(liability.id)).to be true
      expect(asset.reload.property_id).to be_nil
      expect(liability.reload.property_id).to be_nil
    end

    it "keeps the balance sheet lines of the assets it grouped" do
      property = create(:property)
      asset = create(:asset, user: property.user, property: property, asset_type: :real_estate)
      balance_sheet = create(:balance_sheet, user: property.user)
      line = create(:balance_sheet_asset, balance_sheet: balance_sheet, asset: asset, value: 250_000)

      property.destroy

      expect(BalanceSheetAsset.exists?(line.id)).to be true
      expect(balance_sheet.reload.total_assets).to eq(250_000)
    end
  end

  # Les dates du bien sont la période par défaut de ses actifs et de ses passifs
  # (voir Lifespanable) : elles doivent donc les suivre quand le bien les corrige.
  describe "when its dates change" do
    it "moves the lines that still carry the dates of the bien" do
      property = create(:property, acquired_on: Date.new(2019, 3, 4))
      asset = property.real_estate_asset
      liability = create(:liability, user: property.user, property: property)

      property.update!(acquired_on: Date.new(2019, 4, 1), sold_on: Date.new(2025, 2, 28))

      expect(asset.reload.started_on).to eq(Date.new(2019, 4, 1))
      expect(asset.ended_on).to eq(Date.new(2025, 2, 28))
      expect(liability.reload.started_on).to eq(Date.new(2019, 4, 1))
      expect(liability.ended_on).to eq(Date.new(2025, 2, 28))
    end

    it "moves the immobilier asset of the bien too" do
      property = create(:property, acquired_on: Date.new(2019, 3, 4))

      property.update!(sold_on: Date.new(2025, 2, 28))

      expect(property.real_estate_asset.reload.ended_on).to eq(Date.new(2025, 2, 28))
    end

    it "fills a line created before the bien had any date" do
      property = create(:property, acquired_on: nil)
      asset = property.real_estate_asset

      property.update!(acquired_on: Date.new(2019, 3, 4))

      expect(asset.reload.started_on).to eq(Date.new(2019, 3, 4))
    end

    it "leaves alone a bound the user wrote himself" do
      property = create(:property, acquired_on: Date.new(2019, 3, 4))
      asset = property.real_estate_asset
      asset.update!(started_on: Date.new(2021, 1, 1))

      property.update!(acquired_on: Date.new(2019, 4, 1), sold_on: Date.new(2025, 2, 28))

      expect(asset.reload.started_on).to eq(Date.new(2021, 1, 1))
      expect(asset.ended_on).to eq(Date.new(2025, 2, 28))
    end

    it "leaves the lines of another bien alone" do
      property = create(:property, acquired_on: Date.new(2019, 3, 4))
      other = create(:property, user: property.user, acquired_on: Date.new(2019, 3, 4))

      property.update!(sold_on: Date.new(2025, 2, 28))

      expect(other.real_estate_asset.reload.ended_on).to be_nil
    end

    it "leaves the lines alone when the bien changes anything but its dates" do
      property = create(:property, acquired_on: Date.new(2019, 3, 4), usage: :primary_residence)
      asset = property.real_estate_asset

      expect { property.update!(usage: :rental) }.not_to change { asset.reload.updated_at }
    end
  end
end
