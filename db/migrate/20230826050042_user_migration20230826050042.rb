class UserMigration20230826050042 < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :age, :integer
    add_column :users, :zipcode, :integer
    remove_column :users, :extra_col
  end
end
