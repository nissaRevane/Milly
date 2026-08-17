class AddDetailsToProperties < ActiveRecord::Migration[8.0]
  # Descriptive fields of a bien, all optional: the biens already created carry none,
  # and a bien stays usable on the balance sheet without them.
  def change
    add_column :properties, :address, :string
    add_column :properties, :purchase_price, :decimal, precision: 15, scale: 2
    add_column :properties, :acquired_on, :date
  end
end
