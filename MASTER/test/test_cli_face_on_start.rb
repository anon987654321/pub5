# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/cli/face"
require_relative "../lib/cli/face/window"

class TestCliFaceOnStart < Minitest::Test
  def test_the_face_is_never_a_separate_bin_master_entry_mode
    refute Master::CLI::Face::Window.asked?([])
    refute Master::CLI::Face::Window.asked?(["/face"])
    refute Master::CLI::Face::Window.asked?(["face"])
    refute Master::CLI::Face::Window.asked?(["-m", "/face"])
  end

  # The face is the web particle face only (Johann 2026-11-07): the terminal
  # paints no ASCII face, and the /face verb is retired with it. These pin the
  # retirement - the overlay methods are gone from the session, and the closed
  # slash surface has no face verb to resurrect them from.
  def test_the_terminal_paints_no_ascii_face
    session = Master::CLI::Session.allocate

    refute_respond_to session, :face_overlay_text
    refute_respond_to session, :animate_face_intro
  end

  def test_the_slash_surface_has_no_face_verb
    refute_includes Master::CLI::CommandRegistry.slash_commands, "/face"
  end
end
