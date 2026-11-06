# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:391 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bd1476408d287d54
require_relative "master/law/ruby"

Law.define(:STRICT_LOADING_MISSING) do
  path "/app/models/"
  source "Rails strict_loading - N+1 prevention (Rails Guides)"
  scope :file
  absent /\bstrict_loading_by_default\b/
  # The base class is where the default is set, and subclasses inherit it.
  # Matching `< ApplicationRecord` too asked all thirty of amber's models to
  # restate a setting RAILS/__shared/app/models/application_record.rb already
  # makes — the same shape as the `dependent:` census in proposals.yml, which
  # counted declarations whose behaviour comes from the class above them.
  detect { |text| text.match?(/class\s+\w+\s+<\s+ActiveRecord::Base\b/m) }
  fix "Add `self.strict_loading_by_default = true` to surface missing eager-loads."
  bad <<~X
    class ApplicationRecord < ActiveRecord::Base
    end
  X
  good <<~X
    class ApplicationRecord < ActiveRecord::Base
      self.strict_loading_by_default = true
    end
  X
end
