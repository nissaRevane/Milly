# Milly - Personal Balance Sheet Manager

A Ruby on Rails 8 application for managing your personal balance sheet (assets, liabilities, equity).

## Tech Stack

- **Ruby** 3.3 / **Rails** 8.0
- **PostgreSQL** 16
- **Hotwire** (Turbo + Stimulus)
- **Devise** for authentication
- **RSpec** for testing
- **Docker** + **Docker Compose**

## Quick Start

```bash
# Clone the repository
git clone <repo-url> && cd Milly

# Build and start the application
docker-compose build
docker-compose run --rm web rails db:create db:migrate db:seed
docker-compose up
```

Open [http://localhost:3000](http://localhost:3000) in your browser.

### Demo Account

- **Email:** demo@milly.app
- **Password:** password123

## Features

- **Assets management:** Create, edit, delete your assets with risk levels (low/medium/high)
- **Liabilities management:** Create, edit, delete your liabilities with risk levels
- **Balance Sheets:** Create balance sheets with a closing date, add asset/liability lines with values
- **Summary view:** Two-column view organized by risk level showing assets vs liabilities, subtotals, and equity

## Running Tests

```bash
docker-compose run --rm web bundle exec rspec
```

## Project Structure

```
app/
├── controllers/        # All controllers (Assets, Liabilities, BalanceSheets, etc.)
├── models/             # ActiveRecord models with validations and associations
├── views/              # ERB templates with Hotwire
├── helpers/            # View helpers (risk level labels, badges)
├── javascript/         # Stimulus controllers
└── assets/             # CSS styles
config/
├── locales/fr.yml      # French translations
├── routes.rb           # Application routes
└── database.yml        # Database configuration
db/
├── migrate/            # Database migrations
└── seeds.rb            # Seed data
spec/
├── models/             # Model unit tests
├── requests/           # Request/integration tests
└── factories/          # FactoryBot factories
```

## Data Model

- **User** → has many Assets, Liabilities, BalanceSheets
- **Asset** → belongs to User (name, risk_level)
- **Liability** → belongs to User (name, risk_level)
- **BalanceSheet** → belongs to User (closing_date)
- **BalanceSheetAsset** → belongs to BalanceSheet + Asset (value)
- **BalanceSheetLiability** → belongs to BalanceSheet + Liability (remaining_capital)
