# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:750 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ce2739ecd4efa11f
require_relative "master/law/universal"

Law.define(:DIFFERENT_LAYER_DIFFERENT_ABSTRACTION) do
  source "A Philosophy of Software Design - different layers, different abstractions"
  ask "Do adjacent layers merely relay the same abstraction without transforming it?"
  fix "Make each layer add a meaningful abstraction or remove the layer."
  bad <<~'X'
    Controller.call(Service.call(Model.find(id)))
  X
  good <<~'X'
    controller = UsersController.new; controller.show(id)
  X
end
