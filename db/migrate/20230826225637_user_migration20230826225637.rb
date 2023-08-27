class UserMigration20230826225637 < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :address1, :string
    add_column :users, :address2, :string
  end
end
