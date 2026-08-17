class BalanceSheet < ApplicationRecord
  # One property (or the "non rattaché" bucket, where +property+ is nil) seen through
  # this balance sheet: its asset lines, its liability lines and the derived ratios.
  #
  # Amounts are summed in Ruby from the per-line owned_* methods rather than through a
  # SQL SUM: total_assets/total_liabilities need an explicitly rounded SQL expression to
  # stay in step with BigDecimal, and summing the per-line values keeps these blocks
  # identical to what the views already display.
  PropertyPosition = Struct.new(:property, :asset_lines, :liability_lines, keyword_init: true) do
    def gross
      asset_lines.sum(&:owned_value)
    end

    def debt
      liability_lines.sum(&:owned_remaining_capital)
    end

    def net
      gross - debt
    end

    def ltv
      BalanceSheet.ltv_for(gross, debt)
    end

    def unassigned?
      property.nil?
    end
  end

  # One row of the real-estate summary: an usage bucket or the overall total.
  # +ltv+ is carried instead of derived because the overall total deliberately has none.
  UsageTotal = Struct.new(:gross, :debt, :net, :ltv, keyword_init: true)

  # Liability types that belong to a property even when none is linked yet.
  UNASSIGNED_LIABILITY_TYPES = %w[real_estate_loan security_deposit].freeze

  belongs_to :user
  has_many :balance_sheet_assets, dependent: :destroy
  has_many :balance_sheet_liabilities, dependent: :destroy
  has_many :assets, through: :balance_sheet_assets
  has_many :liabilities, through: :balance_sheet_liabilities

  validates :closing_date, presence: true
  validates :closing_date, uniqueness: { scope: :user_id }

  # Single definition of the loan-to-value, shared by a single position (PropertyPosition#ltv)
  # and by an usage bucket (#usage_total) so the two can never drift. It is a class method
  # only because PropertyPosition cannot reach a private instance method of BalanceSheet.
  # nil when there is no gross value to divide by — the view renders an em dash.
  def self.ltv_for(gross, debt)
    return nil if gross.zero?

    (debt / gross * 100).round(1)
  end

  def copy_lines_from(source)
    transaction do
      source.balance_sheet_assets.each do |line|
        balance_sheet_assets.create!(asset_id: line.asset_id, value: line.value)
      end
      source.balance_sheet_liabilities.each do |line|
        balance_sheet_liabilities.create!(liability_id: line.liability_id, remaining_capital: line.remaining_capital)
      end
    end
  end

  def total_assets
    balance_sheet_assets
      .joins(:asset)
      .sum("ROUND(balance_sheet_assets.value * ROUND(assets.ownership_share / 100, 4), 2)")
  end

  def total_liabilities
    balance_sheet_liabilities
      .joins(:liability)
      .sum("ROUND(balance_sheet_liabilities.remaining_capital * ROUND(liabilities.ownership_share / 100, 4), 2)")
  end

  def equity
    total_assets - total_liabilities
  end

  def assets_by_risk_level
    balance_sheet_assets
      .includes(:asset)
      .joins(:asset)
      .order("assets.risk_level ASC, assets.name ASC")
      .group_by { |bsa| bsa.asset.risk_level }
  end

  def assets_by_type
    balance_sheet_assets
      .includes(:asset)
      .joins(:asset)
      .order("assets.asset_type ASC, assets.name ASC")
      .group_by { |bsa| bsa.asset.asset_type }
  end

  def liabilities_by_risk_level
    balance_sheet_liabilities
      .includes(:liability)
      .joins(:liability)
      .order("liabilities.risk_level ASC, liabilities.name ASC")
      .group_by { |bsl| bsl.liability.risk_level }
  end

  def liabilities_by_type
    balance_sheet_liabilities
      .includes(:liability)
      .joins(:liability)
      .order("liabilities.liability_type ASC, liabilities.name ASC")
      .group_by { |bsl| bsl.liability.liability_type }
  end

  # Every property holding at least one line on this balance sheet, ordered by usage
  # then name, followed by the "non rattaché" bucket when it has any line.
  def property_positions
    assets_by_property = property_asset_lines.group_by { |line| line.asset.property }
    liabilities_by_property = property_liability_lines.group_by { |line| line.liability.property }

    properties = (assets_by_property.keys + liabilities_by_property.keys).compact.uniq
    positions = properties
      .sort_by { |property| [Property.usages.fetch(property.usage), property.name] }
      .map do |property|
        PropertyPosition.new(
          property: property,
          asset_lines: assets_by_property.fetch(property, []),
          liability_lines: liabilities_by_property.fetch(property, [])
        )
      end

    unassigned = unassigned_position(assets_by_property[nil].to_a, liabilities_by_property[nil].to_a)
    positions << unassigned if unassigned

    positions
  end

  # Real-estate aggregates for the summary view: an ordered Hash of UsageTotal keyed by
  # usage string, then nil for the unassigned bucket, then :total for the overall row.
  #
  # +positions+ is a parameter so the summary action, which also renders the per-bien
  # detail, computes property_positions once and passes it in instead of paying for the
  # whole aggregation twice.
  #
  # Beware of an asymmetry inherited from #property_positions and kept on purpose: a
  # property bucket takes EVERY line rattachée to that bien whatever its type, while the
  # unassigned bucket only takes the lines whose type says "real estate". You cannot infer
  # that an unlinked compte courant belongs to a bien, but a compte courant the user
  # explicitly attached to one is their statement that it does — so it counts, and it does
  # inflate "Brut". Do not "fix" this by type-filtering the property buckets too.
  def real_estate_totals_by_usage(positions = property_positions)
    grouped = positions.group_by { |position| position.property&.usage }
    ordered_keys = grouped.keys.compact.sort_by { |usage| Property.usages.fetch(usage) }
    ordered_keys << nil if grouped.key?(nil)

    totals = ordered_keys.index_with { |usage| usage_total(grouped.fetch(usage)) }
    # The overall LTV is deliberately nil: mixing a résidence principale with du locatif
    # into a single ratio is not a meaningful metric, so the view renders an em dash.
    totals[:total] = usage_total(positions, ltv: nil)
    totals
  end

  private

  def property_asset_lines
    balance_sheet_assets
      .includes(asset: :property)
      .joins(:asset)
      .order("assets.name ASC")
  end

  def property_liability_lines
    balance_sheet_liabilities
      .includes(liability: :property)
      .joins(:liability)
      .order("liabilities.name ASC")
  end

  # Lines that describe real estate but are not linked to a property yet.
  def unassigned_position(asset_lines, liability_lines)
    asset_lines = asset_lines.select { |line| line.asset.real_estate? }
    liability_lines = liability_lines.select { |line| UNASSIGNED_LIABILITY_TYPES.include?(line.liability.liability_type) }
    return nil if asset_lines.empty? && liability_lines.empty?

    PropertyPosition.new(property: nil, asset_lines: asset_lines, liability_lines: liability_lines)
  end

  def usage_total(positions, ltv: :derive)
    gross = positions.sum(&:gross)
    debt = positions.sum(&:debt)
    ltv = self.class.ltv_for(gross, debt) if ltv == :derive

    UsageTotal.new(gross: gross, debt: debt, net: gross - debt, ltv: ltv)
  end
end
