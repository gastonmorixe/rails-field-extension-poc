# frozen_string_literal: true

puts "Loading 111 #{__FILE__}"

# Provides enforcement of declared field for ActiveRecord models.
module FieldEnforcement
  # Declares an field with enforcement.
  # @param name [Symbol] the name of the attribute
  # @param type [Type] the type of the attribute
  # @param null [Boolean] whether the attribute can be null (default: true)
  # @param default [Object] the default value for the attribute (default: nil)
  # @param options [Hash] additional options passed to the superclass
  # @return [void]
  def field(name, type, null: true, default: nil, **options)
    declared_fields << OpenStruct.new(name: name.to_s, type: type, null: null, default: default)
  end

  def self.extended(base)
    class << base
      def declared_fields
        @_declared_fields ||= []
      end

      def declared_fields=(value)
        @_declared_fields = value
      end
    end

    base.class_eval do
      define_method :enforce_declared_fields do
        database_columns = self.class.column_names
        declared_fields_names = self.class.declared_fields.map(&:name)
        extra_fields = declared_fields_names - database_columns
        missing_fields = database_columns - declared_fields_names

        unless extra_fields.empty?
          raise "Declared fields not found in database schema for #{self.class.name}: #{extra_fields.join(', ')}"
        end

        unless missing_fields.empty?
          raise "fields must be declared in #{self.class.name}: #{missing_fields.join(', ')}"
        end
      end
    end

    base.after_initialize :enforce_declared_fields
  end
end
