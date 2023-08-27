require "field_enforcement"

# The ApplicationRecord class is the base class for all models in the application.
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  extend FieldEnforcement::ClassMethods
  include FieldEnforcement
end
