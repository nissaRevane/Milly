require "rails_helper"

RSpec.describe Asset, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:property).optional }
    it { is_expected.to have_many(:balance_sheet_assets).dependent(:destroy) }
  end

  describe "the property link" do
    it "accepts a property of the same user" do
      property = create(:property)

      expect(build(:asset, user: property.user, property: property)).to be_valid
    end

    it "accepts no property at all" do
      expect(build(:asset, property: nil)).to be_valid
    end

    it "rejects a property belonging to another user" do
      asset = build(:asset, property: create(:property))

      expect(asset).not_to be_valid
      expect(asset.errors[:property]).to eq(["n'est pas valide"])
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }

    it "is invalid with an unknown asset type" do
      asset = build(:asset)
      asset.asset_type = "bogus"
      expect(asset).not_to be_valid
      expect(asset.errors[:asset_type]).to be_present
    end

    it "is invalid without an asset type" do
      asset = build(:asset, asset_type: nil)
      expect(asset).not_to be_valid
      expect(asset.errors[:asset_type]).to be_present
    end

    it "is invalid with an unknown risk level" do
      asset = build(:asset)
      asset.risk_level = "bogus"
      expect(asset).not_to be_valid
      expect(asset.errors[:risk_level]).to be_present
    end

    it "is invalid without a risk level" do
      asset = build(:asset, risk_level: nil)
      expect(asset).not_to be_valid
      expect(asset.errors[:risk_level]).to be_present
    end

    it "is invalid with an ownership share above 100" do
      asset = build(:asset, ownership_share: 101).tap(&:valid?)
      expect(asset).not_to be_valid
      expect(asset.errors[:ownership_share]).to be_present
    end

    it "is invalid with a negative ownership share" do
      asset = build(:asset, ownership_share: -1).tap(&:valid?)
      expect(asset).not_to be_valid
      expect(asset.errors[:ownership_share]).to be_present
    end

    it "is invalid without an ownership share" do
      asset = build(:asset, ownership_share: nil).tap(&:valid?)
      expect(asset).not_to be_valid
      expect(asset.errors[:ownership_share]).to be_present
    end

    it "accepts ownership shares within the 0..100 range" do
      [0, 50.5, 100].each do |share|
        asset = build(:asset, ownership_share: share).tap(&:valid?)
        expect(asset.errors[:ownership_share]).to be_empty
      end
    end
  end

  describe "ownership share" do
    it "defaults to 100 for a new record" do
      expect(Asset.new.ownership_share).to eq(100)
    end

    describe "#share_ratio" do
      it "returns the share as a fraction" do
        expect(build(:asset, ownership_share: 50).share_ratio).to eq(0.5)
        expect(build(:asset, ownership_share: 100).share_ratio).to eq(1)
      end
    end

    describe "#full_ownership?" do
      it "is true only at 100%" do
        expect(build(:asset, ownership_share: 100)).to be_full_ownership
        expect(build(:asset, ownership_share: 50)).not_to be_full_ownership
      end
    end
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:risk_level).with_values(low: 0, medium: 1, high: 2).validating }
    it {
      is_expected.to define_enum_for(:asset_type).with_values(
        cash: 0, checking_account: 1, savings_account: 2, financial_investment: 3, real_estate: 4, receivable: 5
      ).validating
    }
  end

  describe "the immobilier type" do
    describe ".selectable_asset_types" do
      it "leaves it out: only a bien mints it" do
        expect(Asset.selectable_asset_types).to eq(
          %w[cash checking_account savings_account financial_investment receivable]
        )
      end
    end

    it "cannot be adopted by an existing asset" do
      asset = create(:asset, asset_type: :savings_account)

      asset.asset_type = :real_estate

      expect(asset).not_to be_valid
      expect(asset.errors[:asset_type]).to eq(
        ["ne peut être « Immobilier » que pour l'actif créé avec un bien immobilier"]
      )
      expect(asset.reload.asset_type).to eq("savings_account")
    end

    it "cannot be left by the asset of a bien" do
      asset = create(:property).real_estate_asset

      asset.asset_type = :financial_investment

      expect(asset).not_to be_valid
      expect(asset.errors[:asset_type]).to be_present
    end

    it "survives an update that leaves the type alone" do
      asset = create(:property).real_estate_asset

      expect(asset.update(risk_level: :high, ownership_share: 50)).to be true
      expect(asset.reload.asset_type).to eq("real_estate")
    end
  end

  describe "the name of the asset of a bien" do
    it "is the name of the bien, whatever is written on the asset" do
      property = create(:property, name: "Maison")
      asset = property.real_estate_asset

      asset.update!(name: "Autre chose")

      expect(asset.reload.name).to eq("Maison")
    end

    it "is free again once the bien has been deleted" do
      property = create(:property, name: "Maison")
      asset = property.real_estate_asset
      property.destroy

      asset.reload.update!(name: "Ancienne maison")

      expect(asset.reload.name).to eq("Ancienne maison")
    end

    it "leaves the name of an asset merely rattaché to the bien alone" do
      property = create(:property, name: "Maison")
      asset = create(:asset, user: property.user, property: property, name: "Travaux")

      expect(asset.reload.name).to eq("Travaux")
    end
  end

  describe "#owned_by_property?" do
    it "is true for the asset of a bien" do
      expect(create(:property).real_estate_asset).to be_owned_by_property
    end

    it "is false for an immobilier asset whose bien is gone" do
      property = create(:property)
      asset = property.real_estate_asset
      property.destroy

      expect(asset.reload).not_to be_owned_by_property
    end

    it "is false for an asset merely rattaché to a bien" do
      property = create(:property)
      asset = create(:asset, user: property.user, property: property, asset_type: :savings_account)

      expect(asset).not_to be_owned_by_property
    end
  end

  describe "#suggested_value" do
    it "is the purchase price of the bien for its own asset" do
      property = create(:property, purchase_price: 300_000)

      expect(property.real_estate_asset.suggested_value).to eq(300_000)
    end

    it "is nil when the bien has no purchase price" do
      property = create(:property, purchase_price: nil)

      expect(property.real_estate_asset.suggested_value).to be_nil
    end

    it "is nil for an asset merely rattaché to a bien" do
      property = create(:property, purchase_price: 300_000)
      asset = create(:asset, user: property.user, property: property, asset_type: :savings_account)

      expect(asset.suggested_value).to be_nil
    end

    it "is nil for an immobilier asset whose bien is gone" do
      property = create(:property, purchase_price: 300_000)
      asset = property.real_estate_asset
      property.destroy

      expect(asset.reload.suggested_value).to be_nil
    end

    it "is nil for any other asset" do
      expect(build(:asset, asset_type: :checking_account).suggested_value).to be_nil
    end
  end

  describe "#risk_level_label" do
    it "returns the French label for the risk level" do
      asset = build(:asset, risk_level: :medium)
      expect(asset.risk_level_label).to eq("Moyen")
    end
  end

  describe "#asset_type_label" do
    it "returns the French label for the asset type" do
      asset = build(:asset, asset_type: :savings_account)
      expect(asset.asset_type_label).to eq("Compte épargne")
    end

    it "returns the French label for the new types" do
      expect(build(:asset, asset_type: :cash).asset_type_label).to eq("Cash")
      expect(build(:asset, asset_type: :receivable).asset_type_label).to eq("Créance")
    end
  end
end
