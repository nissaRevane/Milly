# Tableau d'amortissement d'un crédit immobilier, calculé à partir des sept
# caractéristiques portées par la dette (Liability::AMORTIZATION_FIELDS).
#
# La première échéance est reprise TELLE QUELLE de la saisie utilisateur : dans la
# pratique elle est presque toujours arbitraire (prorata du mois de déblocage, différé
# partiel, frais intégrés…), aucune formule ne la retrouve. Le calcul ne démarre donc
# qu'à la deuxième échéance : intérêts = CRD × taux/12 arrondis au centime, capital =
# mensualité − intérêts, et le CRD diminue du capital remboursé.
#
# Terminaison : jamais plus de +duration_months+ lignes. La dernière échéance est
# ajustée (capital = CRD) quand le capital calculé dépasserait le CRD, ou, sur la
# dernière ligne contractuelle, quand il ne reste qu'un résidu d'arrondi (moins d'une
# mensualité) à solder. Si la mensualité saisie est trop faible pour amortir le prêt,
# le tableau s'arrête à +duration_months+ lignes avec un CRD encore positif — il rend
# visible l'incohérence plutôt que de la masquer par une échéance ballon.
class AmortizationSchedule
  Row = Struct.new(:number, :due_on, :interest, :principal, :remaining_capital, keyword_init: true)

  def initialize(liability)
    @liability = liability
  end

  def rows
    @rows ||= build_rows
  end

  # Le CRD à une date donnée : le capital emprunté avant la première échéance, puis le
  # CRD de la dernière échéance passée (il ne bouge pas entre deux échéances), et le
  # CRD final (0, ou le résidu d'une mensualité trop faible) après la fin du tableau.
  def remaining_capital_on(date)
    return @liability.borrowed_capital if date < rows.first.due_on

    rows.reverse_each.find { |row| row.due_on <= date }.remaining_capital
  end

  private

  def build_rows
    rows = [first_row]
    monthly_rate = @liability.annual_rate / 100 / 12

    (2..@liability.duration_months).each do |number|
      remaining = rows.last.remaining_capital
      break unless remaining.positive?

      interest = (remaining * monthly_rate).round(2)
      principal = (@liability.monthly_payment - interest).round(2)
      principal = remaining if adjusted_last_payment?(number, principal, remaining)

      rows << Row.new(
        number: number,
        # Date#>> conserve la sémantique de fin de mois (31 janvier + 1 mois = 28 février).
        due_on: @liability.first_payment_on >> (number - 1),
        interest: interest,
        principal: principal,
        remaining_capital: (remaining - principal).round(2)
      )
    end

    rows
  end

  def first_row
    Row.new(
      number: 1,
      due_on: @liability.first_payment_on,
      interest: @liability.first_payment_interest,
      principal: @liability.first_payment_principal,
      remaining_capital: (@liability.borrowed_capital - @liability.first_payment_principal).round(2)
    )
  end

  # L'échéance ajustée qui solde le prêt : quand le capital calculé dépasse le CRD, ou
  # sur la dernière ligne contractuelle quand il ne reste qu'un écart d'arrondi (moins
  # d'une mensualité). Une mensualité trop faible ne déclenche rien : le tableau
  # s'arrête avec un CRD positif plutôt que d'inventer une échéance ballon.
  def adjusted_last_payment?(number, principal, remaining)
    return true if principal >= remaining

    number == @liability.duration_months && (remaining - principal) <= @liability.monthly_payment
  end
end
