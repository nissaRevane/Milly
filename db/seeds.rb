puts "Seeding database..."

# Create a demo user
user = User.find_or_create_by!(email: "demo@milly.app") do |u|
  u.firstname = "Jean"
  u.lastname = "Dupont"
  u.password = "password123"
  u.password_confirmation = "password123"
end

puts "User created: #{user.email}"

# Create assets
assets_data = [
  { name: "Résidence principale", risk_level: :low },
  { name: "Livret A", risk_level: :low },
  { name: "Assurance vie (fonds euros)", risk_level: :low },
  { name: "PEA - ETF World", risk_level: :medium },
  { name: "SCPI Corum Origin", risk_level: :medium },
  { name: "Compte-titres Actions", risk_level: :high },
  { name: "Cryptomonnaies (BTC/ETH)", risk_level: :high }
]

assets = assets_data.map do |data|
  Asset.find_or_create_by!(user: user, name: data[:name]) do |a|
    a.risk_level = data[:risk_level]
  end
end

puts "#{assets.count} assets created"

# Create liabilities
liabilities_data = [
  { name: "Prêt immobilier résidence principale", risk_level: :low },
  { name: "Prêt auto", risk_level: :low },
  { name: "Crédit consommation", risk_level: :medium },
  { name: "Prêt investissement locatif", risk_level: :medium }
]

liabilities = liabilities_data.map do |data|
  Liability.find_or_create_by!(user: user, name: data[:name]) do |l|
    l.risk_level = data[:risk_level]
  end
end

puts "#{liabilities.count} liabilities created"

# Create a balance sheet
bs = BalanceSheet.find_or_create_by!(user: user, closing_date: Date.new(2025, 12, 31))
puts "Balance sheet created: #{bs.closing_date}"

# Add asset lines
asset_values = {
  "Résidence principale" => 350_000,
  "Livret A" => 22_950,
  "Assurance vie (fonds euros)" => 45_000,
  "PEA - ETF World" => 28_500,
  "SCPI Corum Origin" => 15_000,
  "Compte-titres Actions" => 12_000,
  "Cryptomonnaies (BTC/ETH)" => 8_500
}

asset_values.each do |name, value|
  asset = assets.find { |a| a.name == name }
  BalanceSheetAsset.find_or_create_by!(balance_sheet: bs, asset: asset) do |bsa|
    bsa.value = value
  end
end

puts "Balance sheet assets added"

# Add liability lines
liability_values = {
  "Prêt immobilier résidence principale" => 220_000,
  "Prêt auto" => 8_500,
  "Crédit consommation" => 3_200,
  "Prêt investissement locatif" => 95_000
}

liability_values.each do |name, remaining|
  liability = liabilities.find { |l| l.name == name }
  BalanceSheetLiability.find_or_create_by!(balance_sheet: bs, liability: liability) do |bsl|
    bsl.remaining_capital = remaining
  end
end

puts "Balance sheet liabilities added"

total_assets = bs.total_assets
total_liabilities = bs.total_liabilities
equity = bs.equity

puts ""
puts "=== Balance Sheet Summary ==="
puts "Total Assets:      #{total_assets} EUR"
puts "Total Liabilities: #{total_liabilities} EUR"
puts "Equity:            #{equity} EUR"
puts "============================="
puts ""
puts "Done! Login with: demo@milly.app / password123"
