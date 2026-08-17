require "rails_helper"

RSpec.describe AmortizationSchedule do
  let(:liability) { build(:liability, :amortizable) }
  let(:schedule) { described_class.new(liability) }

  describe "#rows" do
    it "reproduces the entered first payment as-is" do
      row = schedule.rows.first

      expect(row.number).to eq(1)
      expect(row.due_on).to eq(Date.new(2024, 3, 5))
      expect(row.interest).to eq(BigDecimal("312.50"))
      expect(row.principal).to eq(BigDecimal("650.00"))
      expect(row.remaining_capital).to eq(BigDecimal("199350"))
    end

    it "derives the second payment from the remaining capital, the monthly rate and the monthly payment" do
      row = schedule.rows[1]

      expect(row.number).to eq(2)
      expect(row.due_on).to eq(Date.new(2024, 4, 5))
      # 199 350 × 3 % / 12 = 498,375 → 498,38
      expect(row.interest).to eq(BigDecimal("498.38"))
      expect(row.principal).to eq(BigDecimal("610.82"))
      expect(row.remaining_capital).to eq(BigDecimal("198739.18"))
    end

    it "keeps month-end semantics when shifting the due dates" do
      liability = build(:liability, :amortizable, first_payment_on: Date.new(2024, 1, 31))

      rows = described_class.new(liability).rows

      expect(rows[1].due_on).to eq(Date.new(2024, 2, 29))
      expect(rows[2].due_on).to eq(Date.new(2024, 3, 31))
    end

    it "never exceeds the contractual duration" do
      expect(schedule.rows.length).to be <= liability.duration_months
      expect(schedule.rows.last.number).to be <= liability.duration_months
    end

    describe "the adjusted final payment" do
      # Petit prêt de 1 000 € sur 6 mois à 3 % : mensualité théorique ≈ 168,13 €.
      let(:small_loan) do
        build(:liability, :amortizable,
              borrowed_capital: 1_000, annual_rate: 3.0, duration_months: 6,
              monthly_payment: 168.13, first_payment_on: Date.new(2024, 1, 10),
              first_payment_principal: 165.63, first_payment_interest: 2.50)
      end

      it "caps the last principal at the prior CRD and ends at zero" do
        rows = described_class.new(small_loan).rows

        expect(rows.length).to eq(6)
        expect(rows.last.principal).to eq(rows[-2].remaining_capital)
        expect(rows.last.remaining_capital).to eq(0)
      end

      it "absorbs the rounding residue on the last contractual row" do
        # Première échéance de 165 € : l'arrondi laisse 0,63 € de CRD au 6e mois, que
        # la dernière échéance contractuelle solde.
        loan = build(:liability, :amortizable,
                     borrowed_capital: 1_000, annual_rate: 3.0, duration_months: 6,
                     monthly_payment: 168.13, first_payment_on: Date.new(2024, 1, 10),
                     first_payment_principal: 165.00, first_payment_interest: 2.50)

        rows = described_class.new(loan).rows

        expect(rows.length).to eq(6)
        expect(rows.last.principal).to eq(rows[-2].remaining_capital)
        expect(rows.last.remaining_capital).to eq(0)
      end
    end

    it "stops at the contractual duration with a positive CRD when the payment is too small" do
      loan = build(:liability, :amortizable,
                   borrowed_capital: 1_000, annual_rate: 3.0, duration_months: 6,
                   monthly_payment: 50, first_payment_on: Date.new(2024, 1, 10),
                   first_payment_principal: 47.50, first_payment_interest: 2.50)

      rows = described_class.new(loan).rows

      expect(rows.length).to eq(6)
      expect(rows.last.remaining_capital).to be > 0
    end
  end

  describe "#remaining_capital_on" do
    it "returns the borrowed capital before the first payment" do
      expect(schedule.remaining_capital_on(Date.new(2024, 3, 4))).to eq(BigDecimal("200000"))
    end

    it "returns the CRD of the first payment on its very day" do
      expect(schedule.remaining_capital_on(Date.new(2024, 3, 5))).to eq(BigDecimal("199350"))
    end

    it "keeps the same CRD until the next due date" do
      expect(schedule.remaining_capital_on(Date.new(2024, 4, 4))).to eq(BigDecimal("199350"))
      expect(schedule.remaining_capital_on(Date.new(2024, 4, 5))).to eq(BigDecimal("198739.18"))
    end

    it "returns zero after the end of the schedule" do
      expect(schedule.remaining_capital_on(Date.new(2050, 1, 1))).to eq(0)
    end
  end
end
