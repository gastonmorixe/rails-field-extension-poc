# frozen_string_literal: true

# Company model
class Company < ApplicationRecord
  field :id, :integer
  field :name, :string
  field :created_at, :datetime
  field :updated_at, :datetime

  has_many :employments
  has_many :employees, through: :employments, source: :user

  def description
    "This is a company called #{name} and has #{employees.size} employees."
  end
end
