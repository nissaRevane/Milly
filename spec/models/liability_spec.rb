require "rails_helper"

RSpec.describe Liability, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:balance_sheet_liabilities).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }

    it "is invalid with an unknown liability type" do
      liability = build(:liability)
      liability.liability_type = "bogus"
      expect(liability).not_to be_valid
      expect(liability.errors[:liability_type]).to be_present
    end

    it "is invalid without a liability type" do
      liability = build(:liability, liability_type: nil)
      expect(liability).not_to be_valid
      expect(liability.errors[:liability_type]).to be_present
    end

    it "is invalid with an unknown risk level" do
      liability = build(:liability)
      liability.risk_level = "bogus"
      expect(liability).not_to be_valid
      expect(liability.errors[:risk_level]).to be_present
    end

    it "is invalid without a risk level" do
      liability = build(:liability, risk_level: nil)
      expect(liability).not_to be_valid
      expect(liability.errors[:risk_level]).to be_present
    end

    it "is invalid with an ownership share above 100" do
      liability = build(:liability, ownership_share: 101).tap(&:valid?)
      expect(liability).not_to be_valid
      expect(liability.errors[:ownership_share]).to be_present
    end

    it "is invalid with a negative ownership share" do
      liability = build(:liability, ownership_share: -1).tap(&:valid?)
      expect(liability).not_to be_valid
      expect(liability.errors[:ownership_share]).to be_present
    end

    it "is invalid without an ownership share" do
      liability = build(:liability, ownership_share: nil).tap(&:valid?)
      expect(liability).not_to be_valid
      expect(liability.errors[:ownership_share]).to be_present
    end

    it "accepts ownership shares within the 0..100 range" do
      [0, 50.5, 100].each do |share|
        liability = build(:liability, ownership_share: share).tap(&:valid?)
        expect(liability.errors[:ownership_share]).to be_empty
      end
    end
  end

  describe "ownership share" do
    it "defaults to 100 for a new record" do
      expect(Liability.new.ownership_share).to eq(100)
    end

    describe "#share_ratio" do
      it "returns the share as a fraction" do
        expect(build(:liability, ownership_share: 50).share_ratio).to eq(0.5)
        expect(build(:liability, ownership_share: 100).share_ratio).to eq(1)
      end
    end

    describe "#full_ownership?" do
      it "is true only at 100%" do
        expect(build(:liability, ownership_share: 100)).to be_full_ownership
        expect(build(:liability, ownership_share: 50)).not_to be_full_ownership
      end
    end
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:risk_level).with_values(low: 0, medium: 1, high: 2).validating }
    it {
      is_expected.to define_enum_for(:liability_type).with_values(
        real_estate_loan: 0, short_term_debt: 1, security_deposit: 2
      ).validating
    }
  end

  describe "#risk_level_label" do
    it "returns the French label for the risk level" do
      liability = build(:liability, risk_level: :high)
      expect(liability.risk_level_label).to eq("Élevé")
    end
  end

  describe "#liability_type_label" do
    it "returns the French label for the liability type" do
      liability = build(:liability, liability_type: :real_estate_loan)
      expect(liability.liability_type_label).to eq("Crédit immobilier")
    end

    it "returns the French label for the other types" do
      expect(build(:liability, liability_type: :short_term_debt).liability_type_label).to eq("Dette court terme")
      expect(build(:liability, liability_type: :security_deposit).liability_type_label).to eq("Dépôt de garantie")
    end
  end
end
