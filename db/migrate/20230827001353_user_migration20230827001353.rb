class UserMigration20230827001353 < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :country, :string
  end
end
