class TodoMigration20230827010119 < ActiveRecord::Migration[7.0]
  def change
    add_column :todos, :content, :string
    add_column :todos, :completed_at, :datetime
  end
end
