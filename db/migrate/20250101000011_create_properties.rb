class CreateProperties < ActiveRecord::Migration[8.0]
  def change
    create_table :properties do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :usage, null: false, default: 0
      t.timestamps
    end
  end
end
