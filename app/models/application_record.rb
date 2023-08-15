# frozen_string_literal: true

require 'field_enforcement'

# The ApplicationRecord class is the base class for all models in the application.
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  extend FieldEnforcement
end
