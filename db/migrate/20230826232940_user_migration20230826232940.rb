class UserMigration20230826232940 < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :is_admin, :boolean
  end
end
