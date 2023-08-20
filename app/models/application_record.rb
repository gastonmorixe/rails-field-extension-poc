# frozen_string_literal: true

require 'field_enforcement'

# The ApplicationRecord class is the base class for all models in the application.
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  extend FieldEnforcement

  # Allows us to define a field without field like this
  #    field :id, ID
  # instead of
  #    field :id, ::GraphQL::Types::ID
  include ::GraphQL::Types

  # TODO Interface PersistedRecord with id, created_at and updated_at which automatically is added here to all subclasses
end
