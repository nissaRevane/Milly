require "json"

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

# Create assets
assets = seed_data["assets"].map do |data|
  Asset.find_or_create_by!(user: user, name: data["name"]) do |a|
    a.risk_level = data["risk_level"]
  end
end

puts "#{assets.count} assets created"

# Create liabilities
liabilities = seed_data["liabilities"].map do |data|
  Liability.find_or_create_by!(user: user, name: data["name"]) do |l|
    l.risk_level = data["risk_level"]
  end
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
