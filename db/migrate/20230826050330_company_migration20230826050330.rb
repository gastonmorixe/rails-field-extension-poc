class CompanyMigration20230826050330 < ActiveRecord::Migration[7.0]
  def change
    add_column :companies, :address, :string
    add_column :companies, :country, :string
  end
end
