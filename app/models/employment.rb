# frozen_string_literal: true

# Employment is a relationship between User and Company
class Employment < ApplicationRecord
  field :id, ID
  field :created_at, ISO8601DateTime
  field :updated_at, ISO8601DateTime

  belongs_to :user
  belongs_to :company
end
