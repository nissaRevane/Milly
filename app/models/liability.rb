class Liability < ApplicationRecord
  include Lifespanable
  include PropertyLinkable
  include RiskCategorizable
  include Shareable

  # Les sept caractéristiques d'amortissement d'un crédit immobilier. Elles vont
  # ensemble : sans l'une d'elles le tableau d'amortissement est incalculable, d'où le
  # tout-ou-rien imposé par la validation ci-dessous.
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
    security_deposit: 2
  }, validate: true

  # Les deux passifs qu'un bien porte réellement : le crédit qui l'a financé et le dépôt de
  # garantie versé par son locataire. Une dette court terme n'est portée par aucun bien
  # (voir PropertyLinkable).
  PROPERTY_LINKABLE_TYPES = %w[real_estate_loan security_deposit].freeze

  validates :name, presence: true
  validate :amortization_fields_all_or_nothing
  validate :amortization_reserved_for_real_estate_loans

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

  def property_linkable?
    PROPERTY_LINKABLE_TYPES.include?(liability_type)
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

  # Seul un crédit immobilier s'amortit par mensualités constantes : les autres types
  # de passifs ne portent pas de tableau d'amortissement.
  def amortization_reserved_for_real_estate_loans
    return unless any_amortization_field?
    return if real_estate_loan?

    errors.add(:liability_type, :amortization_reserved_for_real_estate_loans)
  end

  def first_payment_principal_within_borrowed_capital
    return unless first_payment_principal && borrowed_capital
    return if first_payment_principal <= borrowed_capital

    errors.add(:first_payment_principal, :less_than_or_equal_to, count: borrowed_capital)
  end
end
