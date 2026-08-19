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

  describe "la période d'existence" do
    it "is valid without any date at all" do
      expect(build(:asset, started_on: nil, ended_on: nil)).to be_valid
    end

    it "is valid with a single bound" do
      expect(build(:asset, started_on: Date.new(2020, 1, 1))).to be_valid
      expect(build(:asset, ended_on: Date.new(2020, 1, 1))).to be_valid
    end

    it "accepts an end date on the start date" do
      expect(build(:asset, started_on: Date.new(2020, 1, 1), ended_on: Date.new(2020, 1, 1))).to be_valid
    end

    it "rejects an end date before the start date" do
      asset = build(:asset, started_on: Date.new(2020, 6, 1), ended_on: Date.new(2020, 5, 31))

      expect(asset).not_to be_valid
      expect(asset.errors[:ended_on]).to eq(["ne peut pas précéder la date de début"])
    end

    describe "#available_on?" do
      it "is true for an asset without any bound" do
        expect(build(:asset).available_on?(Date.new(2020, 1, 1))).to be true
      end

      it "is false before the start date" do
        asset = build(:asset, started_on: Date.new(2020, 6, 15))

        expect(asset.available_on?(Date.new(2020, 5, 31))).to be false
      end

      it "is false after the end date" do
        asset = build(:asset, ended_on: Date.new(2020, 6, 15))

        expect(asset.available_on?(Date.new(2020, 7, 1))).to be false
      end

      # La tolérance du mois en cours : la comparaison se fait au mois, jamais au jour.
      it "tolerates any day of the month the asset enters or leaves" do
        entering = build(:asset, started_on: Date.new(2020, 6, 15))
        leaving = build(:asset, ended_on: Date.new(2020, 6, 15))

        expect(entering.available_on?(Date.new(2020, 6, 1))).to be true
        expect(entering.available_on?(Date.new(2020, 6, 30))).to be true
        expect(leaving.available_on?(Date.new(2020, 6, 1))).to be true
        expect(leaving.available_on?(Date.new(2020, 6, 30))).to be true
      end

      it "is true inside both bounds" do
        asset = build(:asset, started_on: Date.new(2020, 1, 1), ended_on: Date.new(2020, 12, 31))

        expect(asset.available_on?(Date.new(2020, 6, 30))).to be true
      end
    end

    describe ".available_on" do
      it "keeps only the assets that existed in the month of the given date" do
        user = create(:user)
        always = create(:asset, user: user)
        entering = create(:asset, user: user, started_on: Date.new(2020, 6, 20))
        gone = create(:asset, user: user, ended_on: Date.new(2020, 5, 4))

        expect(user.assets.available_on(Date.new(2020, 6, 1))).to contain_exactly(always, entering)
        expect(user.assets.available_on(Date.new(2020, 5, 31))).to contain_exactly(always, gone)
      end
    end

    describe "when the asset is rattaché to a bien" do
      it "takes the purchase and sale dates of the bien by default" do
        property = create(:property, acquired_on: Date.new(2019, 3, 4), sold_on: Date.new(2024, 8, 9))

        asset = create(:asset, user: property.user, property: property)

        expect(asset.started_on).to eq(Date.new(2019, 3, 4))
        expect(asset.ended_on).to eq(Date.new(2024, 8, 9))
      end

      it "gives the immobilier asset of a bien the dates of the bien" do
        property = create(:property, acquired_on: Date.new(2019, 3, 4), sold_on: Date.new(2024, 8, 9))

        expect(property.real_estate_asset.started_on).to eq(Date.new(2019, 3, 4))
        expect(property.real_estate_asset.ended_on).to eq(Date.new(2024, 8, 9))
      end

      it "keeps the dates the user wrote himself" do
        property = create(:property, acquired_on: Date.new(2019, 3, 4), sold_on: Date.new(2024, 8, 9))

        asset = create(:asset, user: property.user, property: property, started_on: Date.new(2021, 1, 1))

        expect(asset.started_on).to eq(Date.new(2021, 1, 1))
        expect(asset.ended_on).to eq(Date.new(2024, 8, 9))
      end

      # Le défaut ne vaut qu'à la création : vider une borne est une décision de
      # l'utilisateur, pas un oubli à combler.
      it "does not fill a bound cleared afterwards" do
        property = create(:property, acquired_on: Date.new(2019, 3, 4))
        asset = create(:asset, user: property.user, property: property)

        asset.update!(started_on: nil)

        expect(asset.reload.started_on).to be_nil
      end

      it "leaves an asset attached to no bien without any bound" do
        asset = create(:asset, property: nil)

        expect(asset.started_on).to be_nil
        expect(asset.ended_on).to be_nil
      end
    end
  end
end
