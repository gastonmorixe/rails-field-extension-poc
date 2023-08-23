class UserMigration < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :age, :integer
    add_column :users, :zipcode, :integer
    add_column :users, :notes, :string
  end
end