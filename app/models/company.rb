# frozen_string_literal: true

# Company model
class Company < ApplicationRecord
  field :id, :integer do
    # gql_type ID
  end
  field :name, :string
  # field :description, :string
  field :address, :string
  field :country, :string
  field :phone, :string
  field :created_at, :datetime
  field :updated_at, :datetime

  has_many :employments
  has_many :employees, through: :employments, source: :user

  # TODO if description is defined as method do not add this to the db migration
  # def description
  #   "This is a company called #{name} and has #{employees.size} employees."
  # end
end
