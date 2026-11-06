# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:989 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 92cf09d304a55d8a
require_relative "master/law/universal"

Law.define(:PSYCHOLOGICAL_ACCEPTABILITY) do
  source "Saltzer & Schroeder - psychological acceptability"
  ask "Does the secure path impose enough friction that users are pushed toward an unsafe shortcut?"
  fix "Make the safe path the easy path and remove unnecessary security ceremony."
  bad <<~'X'
    unsafe_url = params[:url] # easier than validating
  X
  good <<~'X'
    url = Url.parse(params[:url]); fetch(url)
  X
end
