# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/interface.rb:128 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 76a8c7a6f77e8708
require_relative "master/law/interface"

Law.define(:CLI_FACE_DEDICATED_TTY) do
  path "MASTER/lib/cli/command_registry.rb"
  source "Terminal discipline - full-screen face must not share line-editor input"
  scope :file
  ask "Does the /face command obtain an independent terminal stream instead of sharing Reline/session stdin with the full-screen face?"
  fix "Open /dev/tty and pass that handle as both the face input and output; close it after the face exits."
  bad <<~'X'
    Face::Window.new(turn:, event_bus: container[:bus]).run
  X
  good <<~'X'
    terminal = File.open("/dev/tty", "r+")
    Face::Window.new(turn:, event_bus: container[:bus], input: terminal, output: terminal).run
  X
  detect do |text|
    text.include?("Face::Window.new") &&
      !text.match?(/File\.open\(["']\/dev\/tty["'],\s*["']r\+["']\)/)
  end
end
