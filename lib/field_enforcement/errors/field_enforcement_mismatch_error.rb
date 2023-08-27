module FieldEnforcement
  module Errors
    class FieldEnforcementMismatchError < FieldEnforcementError
      include ActiveSupport::ActionableError

      action "Save migrations" do
        models = FieldEnforcement::Utils.active_record_models
        models.each do |m|
          m.write_migration
        end
      end

      # action "Run db:migrations" do
      #   ActiveRecord::Tasks::DatabaseTasks.migrate
      # end
    end
  end
end
