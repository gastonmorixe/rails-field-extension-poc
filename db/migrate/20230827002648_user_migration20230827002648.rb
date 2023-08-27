class UserMigration20230827002648 < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :nickname, :string
  end
end
