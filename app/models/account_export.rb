# Serializes a whole account into the db/seed_data.json shape, so an export can be
# fed straight back to db/seeds.rb.
#
# The password is never exported: Devise only ever stores a bcrypt digest, so a
# freshly generated random one takes its place. Re-seeding from an export
# therefore recreates the account with that random password, not the real one.
class AccountExport
  PASSWORD_LENGTH = 24

  def initialize(user)
    @user = user
  end

  def filename
    "milly-export-#{@user.email.parameterize}-#{Date.current.iso8601}.json"
  end

  def to_json
    JSON.pretty_generate(to_h)
  end

  def to_h
    {
      "user" => user_data,
      "properties" => @user.properties.order(:id).map { |property| property_data(property) },
      "assets" => @user.assets.includes(:property).order(:id).map { |asset| asset_data(asset) },
      "liabilities" => @user.liabilities.includes(:property).order(:id).map { |liability| liability_data(liability) },
      "balance_sheets" => balance_sheets_data
    }
  end

  private

  def user_data
    {
      "email" => @user.email,
      "firstname" => @user.firstname,
      "lastname" => @user.lastname,
      "password" => Devise.friendly_token(PASSWORD_LENGTH)
    }
  end

  # The four descriptive fields are optional, and exported even when empty: db/seeds.rb
  # only touches what the file mentions, so writing them always is what makes clearing
  # an address survive an export → import round trip.
  def property_data(property)
    {
      "name" => property.name,
      "usage" => property.usage,
      "address" => property.address,
      "purchase_price" => property.purchase_price && number(property.purchase_price),
      "acquired_on" => property.acquired_on&.iso8601,
      "sold_on" => property.sold_on&.iso8601
    }
  end

  def asset_data(asset)
    {
      "name" => asset.name,
      "risk_level" => asset.risk_level,
      "asset_type" => asset.asset_type,
      "ownership_share" => number(asset.ownership_share),
      "property" => asset.property&.name,
      "started_on" => asset.started_on&.iso8601,
      "ended_on" => asset.ended_on&.iso8601
    }
  end

  # The amortization fields are all-or-nothing on the model, so they are exported the
  # same way: all seven when the loan carries a schedule, none otherwise. db/seeds.rb
  # guards each one with data.key?, so seed files written before they existed stay valid.
  def liability_data(liability)
    data = {
      "name" => liability.name,
      "risk_level" => liability.risk_level,
      "liability_type" => liability.liability_type,
      "ownership_share" => number(liability.ownership_share),
      "property" => liability.property&.name,
      "started_on" => liability.started_on&.iso8601,
      "ended_on" => liability.ended_on&.iso8601
    }

    if liability.amortizable?
      data.merge!(
        "borrowed_capital" => number(liability.borrowed_capital),
        "annual_rate" => number(liability.annual_rate),
        "duration_months" => liability.duration_months,
        "monthly_payment" => number(liability.monthly_payment),
        "first_payment_on" => liability.first_payment_on.iso8601,
        "first_payment_principal" => number(liability.first_payment_principal),
        "first_payment_interest" => number(liability.first_payment_interest)
      )
    end

    data
  end

  def balance_sheets_data
    @user.balance_sheets.order(:closing_date).map do |balance_sheet|
      {
        "closing_date" => balance_sheet.closing_date.iso8601,
        "assets" => lines_for(balance_sheet.balance_sheet_assets.includes(:asset).order(:asset_id)) do |line|
          [line.asset.name, number(line.value)]
        end,
        "liabilities" => lines_for(balance_sheet.balance_sheet_liabilities.includes(:liability).order(:liability_id)) do |line|
          [line.liability.name, number(line.remaining_capital)]
        end
      }
    end
  end

  def lines_for(lines)
    lines.to_h { |line| yield(line) }
  end

  # Keeps whole amounts as integers so the output reads like the hand-written seed
  # file; BigDecimal would otherwise be serialized as a JSON string.
  def number(decimal)
    decimal.to_i == decimal ? decimal.to_i : decimal.to_f
  end
end
