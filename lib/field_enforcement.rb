require "field_enforcement/errors/field_enforcement_error"
require "field_enforcement/errors/field_enforcement_mismatch_error"
require "field_enforcement/errors/field_enforcement_unknown_type_error"
require "field_enforcement/utils/logging"
require "field_enforcement/utils/mappings"
require "field_enforcement/utils/helpers"
require "field_enforcement/class_methods"
require "field_enforcement/instance_methods"

# Provides enforcement of declared field for ActiveRecord models.
module FieldEnforcement
  @processed_classes = {}

  def self.processed_classes
    @processed_classes
  end

  def self.included(base)
    # base.extend(ClassMethods)
    # todo: raise if class methods not found
    base.after_initialize do
      self.class.enforce_declared_fields
    end
  end
end
