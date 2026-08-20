require "rails_helper"

RSpec.describe Liability, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:property).optional }
    it { is_expected.to have_many(:balance_sheet_liabilities).dependent(:destroy) }
  end

  describe "the property link" do
    it "accepts a property of the same user on a crédit immobilier" do
      property = create(:property)

      expect(build(:liability, user: property.user, property: property, liability_type: :real_estate_loan))
        .to be_valid
    end

    # Le dépôt de garantie d'un locataire est porté par le bien qu'il loue.
    it "accepts a property on a dépôt de garantie" do
      property = create(:property, usage: :rental)

      expect(build(:liability, user: property.user, property: property, liability_type: :security_deposit))
        .to be_valid
    end

    it "accepts no property at all" do
      expect(build(:liability, property: nil)).to be_valid
    end

    it "rejects a property belonging to another user" do
      liability = build(:liability, property: create(:property))

      expect(liability).not_to be_valid
      expect(liability.errors[:property]).to eq(["n'est pas valide"])
    end

    # Un autre crédit — auto, travaux, consommation — s'amortit comme un prêt immobilier
    # mais aucun bien ne le porte.
    it "rejects a property on an autre crédit" do
      property = create(:property)
      liability = build(:liability, user: property.user, property: property, liability_type: :other_credit)

      expect(liability).not_to be_valid
      expect(liability.errors[:property]).to eq(
        ["ne se rattache qu'à un crédit immobilier ou à un dépôt de garantie"]
      )
    end

    # Une dette court terme — des travaux à payer, un découvert — n'est portée par aucun
    # bien : elle reste une dette de l'utilisateur.
    it "rejects a property on a dette court terme" do
      property = create(:property)
      liability = build(:liability, user: property.user, property: property, liability_type: :short_term_debt)

      expect(liability).not_to be_valid
      expect(liability.errors[:property]).to eq(
        ["ne se rattache qu'à un crédit immobilier ou à un dépôt de garantie"]
      )
    end
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
    it {
      is_expected.to define_enum_for(:liability_type).with_values(
        real_estate_loan: 0, short_term_debt: 1, security_deposit: 2, other_credit: 3
      ).validating
    }
  end

  describe "amortization terms" do
    it "accepts a real estate loan carrying the seven fields" do
      expect(build(:liability, :amortizable)).to be_valid
    end

    it "accepts a liability carrying none of them" do
      expect(build(:liability)).to be_valid
    end

    it "requires every other field as soon as one is filled" do
      liability = build(:liability, borrowed_capital: 100_000).tap(&:valid?)

      (Liability::AMORTIZATION_FIELDS - [:borrowed_capital]).each do |field|
        expect(liability.errors[field]).to include("doit être rempli(e)")
      end
    end

    it "accepts an autre crédit carrying the seven fields" do
      expect(build(:liability, :amortizable, liability_type: :other_credit)).to be_valid
    end

    it "reserves the fields for credits" do
      liability = build(:liability, :amortizable, liability_type: :security_deposit).tap(&:valid?)

      expect(liability.errors[:liability_type])
        .to include("doit être « Crédit immobilier » ou « Autres crédits » pour porter un tableau d'amortissement")
    end

    it "rejects non-positive amounts and durations" do
      liability = build(:liability, :amortizable,
                        borrowed_capital: 0, monthly_payment: -1, duration_months: 0,
                        annual_rate: -1, first_payment_interest: -1).tap(&:valid?)

      expect(liability.errors[:borrowed_capital]).to include("doit être supérieur à 0")
      expect(liability.errors[:monthly_payment]).to be_present
      expect(liability.errors[:duration_months]).to be_present
      expect(liability.errors[:annual_rate]).to be_present
      expect(liability.errors[:first_payment_interest]).to be_present
    end

    it "rejects a fractional duration" do
      liability = build(:liability, :amortizable, duration_months: 12.5).tap(&:valid?)

      expect(liability.errors[:duration_months]).to include("doit être un nombre entier")
    end

    it "rejects a first payment principal above the borrowed capital" do
      liability = build(:liability, :amortizable, first_payment_principal: 200_001).tap(&:valid?)

      expect(liability.errors[:first_payment_principal]).to be_present
    end

    it "accepts a zero rate" do
      expect(build(:liability, :amortizable, annual_rate: 0)).to be_valid
    end
  end

  describe "#amortizable_type?" do
    it "answers on the type alone, whatever the fields hold" do
      expect(build(:liability, liability_type: :real_estate_loan)).to be_amortizable_type
      expect(build(:liability, liability_type: :other_credit)).to be_amortizable_type
      expect(build(:liability, liability_type: :short_term_debt)).not_to be_amortizable_type
      expect(build(:liability, liability_type: :security_deposit)).not_to be_amortizable_type
    end
  end

  # Seul le dépôt de garantie est couvert par une trésorerie du même montant : c'est ce qui
  # le tient hors de la valeur nette du bien qui le porte.
  describe "#cash_backed?" do
    it "holds for the dépôt de garantie alone" do
      expect(build(:liability, liability_type: :security_deposit)).to be_cash_backed
      expect(build(:liability, liability_type: :real_estate_loan)).not_to be_cash_backed
      expect(build(:liability, liability_type: :short_term_debt)).not_to be_cash_backed
      expect(build(:liability, liability_type: :other_credit)).not_to be_cash_backed
    end
  end

  describe "#amortizable?" do
    it "is true only when the seven fields are present" do
      expect(build(:liability, :amortizable)).to be_amortizable
      expect(build(:liability)).not_to be_amortizable
      expect(build(:liability, :amortizable, monthly_payment: nil)).not_to be_amortizable
    end
  end

  describe "#amortization_schedule" do
    it "returns a memoized schedule when amortizable" do
      liability = build(:liability, :amortizable)

      expect(liability.amortization_schedule).to be_a(AmortizationSchedule)
      expect(liability.amortization_schedule).to equal(liability.amortization_schedule)
    end

    it "returns nil when not amortizable" do
      expect(build(:liability).amortization_schedule).to be_nil
    end
  end

  describe "#suggested_remaining_capital" do
    it "returns nil when the liability carries no amortization terms" do
      expect(build(:liability).suggested_remaining_capital(Date.new(2025, 1, 1))).to be_nil
    end

    it "derives the CRD from the schedule at the given date" do
      liability = build(:liability, :amortizable)

      expect(liability.suggested_remaining_capital(Date.new(2024, 3, 10))).to eq(BigDecimal("199350"))
      expect(liability.suggested_remaining_capital(Date.new(2024, 4, 5))).to eq(BigDecimal("198739.18"))
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
      expect(build(:liability, liability_type: :other_credit).liability_type_label).to eq("Autres crédits")
    end
  end

  # La période d'existence est partagée avec Asset (Lifespanable), qui la couvre en détail ;
  # ce qui est vérifié ici, c'est qu'un passif la porte bel et bien.
  describe "la période d'existence" do
    it "is valid without any date at all" do
      expect(build(:liability, started_on: nil, ended_on: nil)).to be_valid
    end

    it "rejects an end date before the start date" do
      liability = build(:liability, started_on: Date.new(2020, 6, 1), ended_on: Date.new(2020, 5, 31))

      expect(liability).not_to be_valid
      expect(liability.errors[:ended_on]).to eq(["ne peut pas précéder la date de début"])
    end

    it "takes the purchase and sale dates of the bien by default" do
      property = create(:property, acquired_on: Date.new(2019, 3, 4), sold_on: Date.new(2024, 8, 9))

      liability = create(:liability, user: property.user, property: property)

      expect(liability.started_on).to eq(Date.new(2019, 3, 4))
      expect(liability.ended_on).to eq(Date.new(2024, 8, 9))
    end

    it "keeps only the liabilities that existed in the month of the given date" do
      user = create(:user)
      running = create(:liability, user: user)
      repaid = create(:liability, user: user, ended_on: Date.new(2020, 5, 4))

      expect(user.liabilities.available_on(Date.new(2020, 6, 1))).to contain_exactly(running)
      expect(user.liabilities.available_on(Date.new(2020, 5, 31))).to contain_exactly(running, repaid)
    end
  end
end
