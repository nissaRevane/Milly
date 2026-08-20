require "rails_helper"

RSpec.describe BreakdownCategory do
  describe ".for_asset" do
    it "gathers every asset one can spend today under les liquidités" do
      keys = %i[cash checking_account savings_account receivable].map { |type|
        described_class.for_asset(build(:asset, asset_type: type))
      }

      expect(keys.uniq).to eq(["liquidity"])
    end

    it "keeps les placements financiers a family of their own" do
      expect(described_class.for_asset(build(:asset, asset_type: :financial_investment)))
        .to eq("financial_investment")
    end

    # La seule famille éclatée : une résidence principale et un locatif ne se pilotent pas de
    # la même façon, et c'est l'usage du bien qui le dit.
    it "splits the immobilier by the usage of its bien" do
      property = create(:property, name: "Studio", usage: :rental)

      expect(described_class.for_asset(property.real_estate_asset)).to eq("real_estate:rental")
    end

    it "files an immobilier line no bien carries under the unassigned bucket" do
      expect(described_class.for_asset(build(:asset, asset_type: :real_estate, property: nil)))
        .to eq("real_estate:unassigned")
    end
  end

  describe ".for_liability" do
    it "gathers la dette court terme and les autres crédits under les dettes diverses" do
      keys = %i[short_term_debt other_credit].map { |type|
        described_class.for_liability(build(:liability, liability_type: type))
      }

      expect(keys.uniq).to eq(["short_term_debt"])
    end

    it "splits the crédit immobilier by the usage of the bien it finances" do
      property = create(:property, name: "Studio", usage: :rental)
      loan = build(:liability, liability_type: :real_estate_loan, property: property)

      expect(described_class.for_liability(loan)).to eq("real_estate_loan:rental")
    end

    it "leaves les dépôts de garantie whole, bien or no bien" do
      property = create(:property, name: "Studio", usage: :rental)
      deposit = build(:liability, liability_type: :security_deposit, property: property)

      expect(described_class.for_liability(deposit)).to eq("security_deposit")
    end
  end

  describe ".keys" do
    it "orders the categories as the graph stacks them, the immobilier by usage" do
      expect(described_class.keys(described_class::ASSETS)).to eq(
        ["liquidity",
         "real_estate:primary_residence", "real_estate:secondary_residence",
         "real_estate:rental", "real_estate:unassigned",
         "financial_investment"]
      )
    end

    it "orders the dette from what no bien carries to the crédits and their detail" do
      expect(described_class.keys(described_class::LIABILITIES)).to eq(
        ["short_term_debt", "security_deposit",
         "real_estate_loan:primary_residence", "real_estate_loan:secondary_residence",
         "real_estate_loan:rental", "real_estate_loan:unassigned"]
      )
    end
  end

  describe ".full_label" do
    it "names a whole family in one piece" do
      expect(described_class.full_label("liquidity")).to eq("Liquidités")
    end

    it "hangs the usage of the bien behind the family it splits" do
      expect(described_class.full_label("real_estate:rental")).to eq("Immobilier · Locatif")
      expect(described_class.full_label("real_estate_loan:unassigned")).to eq("Crédit immobilier · Non rattaché")
    end
  end

  describe ".types_for" do
    it "returns the enum types a family holds, for the clause of a filter" do
      expect(described_class.types_for(described_class::ASSETS, "liquidity"))
        .to eq(%w[cash checking_account savings_account receivable])
      expect(described_class.types_for(described_class::LIABILITIES, "short_term_debt"))
        .to eq(%w[short_term_debt other_credit])
    end
  end

  # Un type ajouté à un enum sans être rangé dans une catégorie doit casser la suite de tests
  # plutôt que de disparaître en silence d'un écran qui prétend tout montrer.
  describe "the coverage of the enums" do
    it "ranges every asset type under a category" do
      expect(described_class::ASSETS.flat_map { |category| category[:types] })
        .to match_array(Asset.asset_types.keys)
    end

    it "ranges every liability type under a category" do
      expect(described_class::LIABILITIES.flat_map { |category| category[:types] })
        .to match_array(Liability.liability_types.keys)
    end
  end
end
