require "json"

# bin/docker-entrypoint lance `db:prepare` a chaque demarrage, et db:prepare
# enchaine sur db:seed la premiere fois (base tout juste creee). En production
# cela injecterait le jeu de demonstration dans la vraie base : on s'arrete la,
# sauf demande explicite.
if Rails.env.production? && ENV["ALLOW_PRODUCTION_SEED"] != "true"
  puts "Seeds ignores en production (ALLOW_PRODUCTION_SEED=true pour forcer)."
  return
end

puts "Seeding database..."

seed_data = JSON.parse(File.read(Rails.root.join("db", "seed_data.json")))

# Create user
user_data = seed_data["user"]
user = User.find_or_create_by!(email: user_data["email"]) do |u|
  u.firstname = user_data["firstname"]
  u.lastname = user_data["lastname"]
  u.password = user_data["password"]
  u.password_confirmation = user_data["password"]
end

puts "User created: #{user.email}"

# Create properties (before assets and liabilities, which reference them by name)
properties = seed_data.fetch("properties", []).map do |data|
  property = Property.find_or_initialize_by(user: user, name: data["name"])
  property.usage = data["usage"]
  # Only touched when the seed file says something about them: seeding is re-runnable,
  # and a file written before these fields existed must not erase what the UI has set.
  %w[address purchase_price acquired_on sold_on].each do |field|
    property[field] = data[field] if data.key?(field)
  end
  property.save!
  property
end

puts "#{properties.count} properties created"

# Looks a property up by name; seed files written before properties existed have no key.
find_property = ->(data) { properties.find { |p| p.name == data["property"] } if data["property"].present? }

# Create assets
assets = seed_data["assets"].map do |data|
  asset = Asset.find_or_initialize_by(user: user, name: data["name"])
  asset.asset_type = data["asset_type"]
  asset.ownership_share = data.fetch("ownership_share", 100)
  # Only touched when the seed file says something about it: seeding is re-runnable, and
  # a file written before properties existed must not unlink what the UI has linked since.
  asset.property = find_property.call(data) if data.key?("property")
  # Période d'existence, seulement quand le fichier en parle : sans ces clés, un actif
  # rattaché à un bien reprend les dates du bien (voir Lifespanable).
  %w[started_on ended_on].each do |field|
    asset[field] = data[field] if data.key?(field)
  end
  asset.save!
  asset
end

puts "#{assets.count} assets created"

# Create liabilities
liabilities = seed_data["liabilities"].map do |data|
  liability = Liability.find_or_initialize_by(user: user, name: data["name"])
  liability.liability_type = data["liability_type"]
  liability.ownership_share = data.fetch("ownership_share", 100)
  # See the asset loop above: absent key means "leave the link alone".
  liability.property = find_property.call(data) if data.key?("property")
  %w[started_on ended_on].each do |field|
    liability[field] = data[field] if data.key?(field)
  end
  # Amortization fields, only touched when the seed file mentions them: a file written
  # before they existed must not erase a schedule the UI has defined since.
  Liability::AMORTIZATION_FIELDS.map(&:to_s).each do |field|
    liability[field] = data[field] if data.key?(field)
  end
  liability.save!
  liability
end

puts "#{liabilities.count} liabilities created"

# Create balance sheets with their assets and liabilities
seed_data["balance_sheets"].each do |bs_data|
  closing_date = Date.parse(bs_data["closing_date"])
  bs = BalanceSheet.find_or_create_by!(user: user, closing_date: closing_date)
  puts "Balance sheet created: #{bs.closing_date}"

  bs_data["assets"].each do |name, value|
    asset = assets.find { |a| a.name == name }
    BalanceSheetAsset.find_or_create_by!(balance_sheet: bs, asset: asset) do |bsa|
      bsa.value = value
    end
  end

  bs_data["liabilities"].each do |name, remaining|
    liability = liabilities.find { |l| l.name == name }
    BalanceSheetLiability.find_or_create_by!(balance_sheet: bs, liability: liability) do |bsl|
      bsl.remaining_capital = remaining
    end
  end

  puts "  Assets: #{bs.total_assets} EUR | Liabilities: #{bs.total_liabilities} EUR | Equity: #{bs.equity} EUR"
end

puts ""
puts "#{seed_data["balance_sheets"].count} balance sheets created"
puts "Done! Login with: #{user_data["email"]} / #{user_data["password"]}"
