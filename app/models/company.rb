# Company model
class Company < ApplicationRecord
  field :id, :integer
  field :created_at, :datetime
  field :updated_at, :datetime
  field :name, :string
  field :description, :string
  field :address, :string
  field :country, :string
  field :phone, :string
  field :hello, :string

  has_many :employments
  has_many :employees, through: :employments, source: :user

  # TODO: if description is defined as method do not add this to the db migration
  def hello
    "This is a company called #{name} and has #{employees.size} employees."
  end
end
