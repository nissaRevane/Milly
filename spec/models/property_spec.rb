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
end
