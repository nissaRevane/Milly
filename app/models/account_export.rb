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
      "assets" => @user.assets.order(:id).map { |asset| asset_data(asset) },
      "liabilities" => @user.liabilities.order(:id).map { |liability| liability_data(liability) },
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

  def asset_data(asset)
    {
      "name" => asset.name,
      "risk_level" => asset.risk_level,
      "asset_type" => asset.asset_type,
      "ownership_share" => number(asset.ownership_share)
    }
  end

  def liability_data(liability)
    {
      "name" => liability.name,
      "risk_level" => liability.risk_level,
      "liability_type" => liability.liability_type,
      "ownership_share" => number(liability.ownership_share)
    }
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
