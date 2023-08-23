class CompanyMigration < ActiveRecord::Migration[7.0]
  def change
    add_column :companies, :phone, :integer
    remove_column :companies, :description
  end
end