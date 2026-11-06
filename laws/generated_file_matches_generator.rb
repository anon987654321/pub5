# frozen_string_literal: true

require_relative "../master/contracts/contracts"

# A generated file is regenerated, never edited: registry/paths.yml names
# each one and its sources, and this Law fails any byte that differs from
# what `bin/master generate` would write. pub4 learned this with
# vm_resource.yml, which said it mirrored resource_guard.sh while carrying
# "three recalibrations that never reached this file".
Law.define(:GENERATED_FILE_MATCHES_GENERATOR) do
  source "PLAN.md section 4 (registries): a Law fails any hand edit to a generated file"
  languages :markdown
  example_path "AGENTS.md"
  check do |text, file|
    next [] unless Contracts.generated?(file)
    next [] if text == Contracts.render(file)

    [finding(line: 1, message: "differs from its generator; run bin/master generate")]
  end
  fix "Edit the sources named in registry/paths.yml, then run bin/master generate."
  bad "# AGENTS.md\n\nEdited by hand.\n"
  good -> { Contracts.render("AGENTS.md") }
end
