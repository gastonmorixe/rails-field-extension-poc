# frozen_string_literal: true

# Employment is a relationship between User and Company
class Employment < ApplicationRecord
  field :id, :integer
  field :created_at, :datetime
  field :updated_at, :datetime

  belongs_to :user
  belongs_to :company
end
