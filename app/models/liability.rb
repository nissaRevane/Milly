class Liability < ApplicationRecord
  include Historizable
  include Lifespanable
  include PropertyLinkable
  include Shareable

  # Les sept caractéristiques d'amortissement d'un crédit. Elles vont ensemble : sans
  # l'une d'elles le tableau d'amortissement est incalculable, d'où le tout-ou-rien
  # imposé par la validation ci-dessous.
  AMORTIZATION_FIELDS = %i[
    borrowed_capital
    annual_rate
    duration_months
    monthly_payment
    first_payment_on
    first_payment_principal
    first_payment_interest
  ].freeze

  belongs_to :user
  has_many :balance_sheet_liabilities, dependent: :destroy

  enum :liability_type, {
    real_estate_loan: 0,
    short_term_debt: 1,
    security_deposit: 2,
    other_credit: 3
  }, validate: true

  # Les deux passifs qu'un bien porte réellement : le crédit qui l'a financé et le dépôt de
  # garantie versé par son locataire. Une dette court terme n'est portée par aucun bien
  # (voir PropertyLinkable).
  PROPERTY_LINKABLE_TYPES = %w[real_estate_loan security_deposit].freeze

  # Les deux types de crédits qui s'amortissent par mensualités constantes : le prêt
  # immobilier, porté par le bien qu'il finance, et l'« autre crédit » — auto, travaux,
  # consommation — qu'aucun bien ne porte (voir PROPERTY_LINKABLE_TYPES). Les autres
  # passifs, dette court terme et dépôt de garantie, n'ont pas d'échéancier : leur montant
  # se saisit bilan par bilan.
  AMORTIZABLE_TYPES = %w[real_estate_loan other_credit].freeze

  # Les passifs adossés à une trésorerie du même montant, qu'aucun actif ne nomme : le dépôt
  # de garantie d'un locataire est bien une dette — elle sera rendue — mais l'argent qui la
  # couvre dort sur un compte courant, mélangé au reste, sans ligne à lui. Cette dette pèse
  # donc sur le patrimoine global, où le compte courant qui la détient est compté lui aussi,
  # mais pas sur la valeur nette du bien qui la porte : la retrancher de la valeur du bien
  # ferait perdre au bien une somme qu'il ne paie pas (voir BalanceSheet::PropertyPosition).
  CASH_BACKED_TYPES = %w[security_deposit].freeze

  validates :name, presence: true
  validate :amortization_fields_all_or_nothing
  validate :amortization_reserved_for_credits

  with_options if: :any_amortization_field? do
    validates :borrowed_capital, numericality: { greater_than: 0 }, allow_nil: true
    validates :annual_rate, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validates :duration_months, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validates :monthly_payment, numericality: { greater_than: 0 }, allow_nil: true
    validates :first_payment_principal, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validates :first_payment_interest, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validate :first_payment_principal_within_borrowed_capital
  end

  def self.liability_type_label_for(type)
    EnumLabel.for("liability_types", type)
  end

  def liability_type_label
    self.class.liability_type_label_for(liability_type)
  end

  # Voir Asset#category_key : la même catégorie, côté dette.
  def category_key
    BreakdownCategory.for_liability(self)
  end

  def self.ordered_by_category
    BreakdownCategory.sort(includes(:property), BreakdownCategory::LIABILITIES)
  end

  def property_linkable?
    PROPERTY_LINKABLE_TYPES.include?(liability_type)
  end

  # Ce type de passif peut-il porter un tableau d'amortissement ? La question porte sur le
  # TYPE seul — le formulaire s'en sert pour montrer ou masquer le bloc de saisie — là où
  # #amortizable? répond sur les champs effectivement renseignés.
  def amortizable_type?
    AMORTIZABLE_TYPES.include?(liability_type)
  end

  # Ce passif est-il couvert par une trésorerie de même montant ? Voir CASH_BACKED_TYPES.
  def cash_backed?
    CASH_BACKED_TYPES.include?(liability_type)
  end

  def amortizable?
    AMORTIZATION_FIELDS.all? { |field| self[field].present? }
  end

  def amortization_schedule
    return nil unless amortizable?

    @amortization_schedule ||= AmortizationSchedule.new(self)
  end

  # Le capital restant dû proposé quand ce passif entre dans un bilan clos à +date+,
  # nil quand le prêt ne porte pas de tableau d'amortissement. Ce n'est qu'une
  # suggestion — le bilan reste ce que l'utilisateur y écrit.
  def suggested_remaining_capital(date)
    amortization_schedule&.remaining_capital_on(date)
  end

  private

  # Voir Historizable : les lignes de bilan de ce passif, et le capital détenu qu'elles portent.
  def historized_lines
    balance_sheet_liabilities
  end

  def historized_amount(line)
    line.owned_remaining_capital
  end

  def any_amortization_field?
    AMORTIZATION_FIELDS.any? { |field| self[field].present? }
  end

  # Un tableau d'amortissement partiel ne se calcule pas : dès qu'un champ est saisi,
  # tous les autres deviennent obligatoires.
  def amortization_fields_all_or_nothing
    filled = AMORTIZATION_FIELDS.select { |field| self[field].present? }
    return if filled.empty? || filled.size == AMORTIZATION_FIELDS.size

    (AMORTIZATION_FIELDS - filled).each { |field| errors.add(field, :blank) }
  end

  # Seul un crédit s'amortit par mensualités constantes : les autres types de passifs ne
  # portent pas de tableau d'amortissement.
  def amortization_reserved_for_credits
    return unless any_amortization_field?
    return if amortizable_type?

    errors.add(:liability_type, :amortization_reserved_for_credits)
  end

  def first_payment_principal_within_borrowed_capital
    return unless first_payment_principal && borrowed_capital
    return if first_payment_principal <= borrowed_capital

    errors.add(:first_payment_principal, :less_than_or_equal_to, count: borrowed_capital)
  end
end
