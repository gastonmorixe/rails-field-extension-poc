class CompanyMigration20230826225238 < ActiveRecord::Migration[7.0]
  def change
    add_column :companies, :description, :string
  end
end
