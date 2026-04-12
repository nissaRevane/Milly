# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_01_01_000006) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "assets", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.integer "risk_level", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_assets_on_user_id"
  end

  create_table "balance_sheet_assets", force: :cascade do |t|
    t.bigint "balance_sheet_id", null: false
    t.bigint "asset_id", null: false
    t.decimal "value", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_id"], name: "index_balance_sheet_assets_on_asset_id"
    t.index ["balance_sheet_id", "asset_id"], name: "index_balance_sheet_assets_on_balance_sheet_id_and_asset_id", unique: true
    t.index ["balance_sheet_id"], name: "index_balance_sheet_assets_on_balance_sheet_id"
  end

  create_table "balance_sheet_liabilities", force: :cascade do |t|
    t.bigint "balance_sheet_id", null: false
    t.bigint "liability_id", null: false
    t.decimal "remaining_capital", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["balance_sheet_id", "liability_id"], name: "idx_bs_liabilities_on_bs_and_liability", unique: true
    t.index ["balance_sheet_id"], name: "index_balance_sheet_liabilities_on_balance_sheet_id"
    t.index ["liability_id"], name: "index_balance_sheet_liabilities_on_liability_id"
  end

  create_table "balance_sheets", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.date "closing_date", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "closing_date"], name: "index_balance_sheets_on_user_id_and_closing_date", unique: true
    t.index ["user_id"], name: "index_balance_sheets_on_user_id"
  end

  create_table "liabilities", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.integer "risk_level", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_liabilities_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "firstname", default: "", null: false
    t.string "lastname", default: "", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "assets", "users"
  add_foreign_key "balance_sheet_assets", "assets"
  add_foreign_key "balance_sheet_assets", "balance_sheets"
  add_foreign_key "balance_sheet_liabilities", "balance_sheets"
  add_foreign_key "balance_sheet_liabilities", "liabilities"
  add_foreign_key "balance_sheets", "users"
  add_foreign_key "liabilities", "users"
end
