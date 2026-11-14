# frozen_string_literal: true

require "minitest/autorun"

# The "file" message type was declared and unreachable: the validator took only
# image and audio, so a document could never attach. The contract is now a PDF
# and nothing else, mapped to its own type, refused before storage — read from
# source because the suite has no Rails boot for these controllers.
class MessageFileAttachmentTest < Minitest::Test
  MODEL = File.expand_path("../../app/models/message.rb", __dir__)
  THREAD_PARTIAL = File.expand_path("../../../../brgen/app/views/messages/_message.html.erb", __dir__)
  COMPOSER = File.expand_path("../../../../brgen/app/views/conversations/_composer.html.erb", __dir__)

  def test_a_pdf_is_an_allowed_attachment_type
    assert_includes File.read(MODEL, encoding: "UTF-8"), "application/pdf"
  end

  def test_the_allowed_type_regex_admits_pdf_and_no_other_document_type
    regex_line = File.read(MODEL, encoding: "UTF-8")[/ATTACHMENT_TYPE = .+$/].to_s
    assert_includes regex_line, "application/pdf"
    %w[text/plain application/zip text/html application/msword].each do |type|
      refute_includes regex_line, type
    end
  end

  def test_a_pdf_maps_to_the_file_message_type
    assert_includes File.read(MODEL, encoding: "UTF-8"),
                    'self.message_type = "file" if content_type == "application/pdf"'
  end

  def test_the_file_type_stays_in_the_declared_type_list
    assert_match(/message_type, inclusion: \{ in: %w\[text image file audio\] \}/,
                 File.read(MODEL, encoding: "UTF-8"))
  end

  def test_the_thread_renders_a_file_as_a_download_chip
    partial = File.read(THREAD_PARTIAL, encoding: "UTF-8")
    assert_includes partial, 'message.message_type == "file"'
    assert_match(/download: message\.attachment\.filename/, partial)
    assert_match(/number_to_human_size/, partial)
  end

  def test_the_composer_offers_documents_beside_photos
    assert_includes File.read(COMPOSER, encoding: "UTF-8"),
                    'accept: "audio/*,image/*,application/pdf"'
  end
end
