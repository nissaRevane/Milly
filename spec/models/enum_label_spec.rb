require "rails_helper"

RSpec.describe EnumLabel do
  describe ".for" do
    it "returns the French label for a known risk level key" do
      expect(described_class.for("risk_levels", "low")).to eq("Faible")
      expect(described_class.for("risk_levels", "high")).to eq("Élevé")
    end

    it "returns the French label for a known liability type key" do
      expect(described_class.for("liability_types", "real_estate_loan")).to eq("Crédit immobilier")
      expect(described_class.for("liability_types", "security_deposit")).to eq("Dépôt de garantie")
    end

    it "accepts symbol values" do
      expect(described_class.for("risk_levels", :medium)).to eq("Moyen")
      expect(described_class.for("liability_types", :short_term_debt)).to eq("Dette court terme")
    end

    it "returns the raw string for an unknown key rather than a translation-missing message" do
      expect(described_class.for("risk_levels", "bogus")).to eq("bogus")
      expect(described_class.for("liability_types", "bogus")).to eq("bogus")
    end

    it "returns an empty string for nil" do
      expect(described_class.for("risk_levels", nil)).to eq("")
      expect(described_class.for("liability_types", nil)).to eq("")
    end

    it "returns an empty string for a blank value" do
      expect(described_class.for("risk_levels", "")).to eq("")
      expect(described_class.for("liability_types", "")).to eq("")
    end
  end
end
