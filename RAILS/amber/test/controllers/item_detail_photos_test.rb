# frozen_string_literal: true

require "test_helper"
require "base64"

# Every photo of a garment carried the same alt and its lightbox link no name
# of its own; the colour swatch and the palette chips set their colour in a
# style attribute, which a CSP without 'unsafe-inline' refuses; and a palette
# chip had no colour name for a screen reader, only a hover title naming the item.
class ItemDetailPhotosTest < ActionDispatch::IntegrationTest
  GPS_JPEG = Base64.strict_decode64([
    "/9j/4AAQSkZJRgABAQAAAQABAAD/4QCIRXhpZgAATU0AKgAAAAgAAYglAAQAAAABAAAAGgAAAAAABAABAAIAAAACTgAAAAAC",
    "AAUAAAADAAAAUAADAAIAAAACRQAAAAAEAAUAAAADAAAAaAAAAAAAAAA8AAAAAQAAAAAAAAABAAAAAAAAAAEAAAAFAAAAAQAA",
    "AAAAAAABAAAAAAAAAAH/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0",
    "Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy",
    "MjIyMjIyMjIyMjL/wAARCAAMAAwDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgED",
    "AwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RF",
    "RkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJ",
    "ytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgEC",
    "BAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNE",
    "RUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbH",
    "yMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDlqKKK9A5D/9k=",
  ].join)
  setup do
    email = "photos-#{SecureRandom.hex(4)}@example.test"
    @user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
    @item = @user.items.create!(title: "Wool coat", category: "Outerwear", color: "navy")
  end

  def attach_photos(count)
    count.times do |index|
      @item.photos.attach(io: StringIO.new("photo-#{index}"), filename: "coat-#{index}.jpg", content_type: "image/jpeg")
    end
  end

  test "every display derivative keeps only the ICC colour profile" do
    Item::PHOTO_VARIANTS.each_value do |transformations|
      assert_equal 8, transformations.dig(:saver, :keep)
    end
    assert_same Item::PHOTO_VARIANTS, Outfit::IMAGE_VARIANTS
  end

  test "several photos are numbered in their alt text and their lightbox links" do
    attach_photos(2)

    get item_path(@item)
    assert_response :success
    [ 1, 2 ].each do |position|
      numbered = { title: "Wool coat", position:, count: 2 }
      assert_select "[data-controller=lightbox] a[aria-label=?] img[alt=?]",
                    I18n.t("items.open_photo", **numbered), I18n.t("items.photo_numbered", **numbered)
    end
  end

  test "a single photo is simply the garment" do
    attach_photos(1)

    get item_path(@item)
    assert_select "[data-controller=lightbox] a:not([aria-label]) img[alt=?]", "Wool coat"
  end

  test "the colour swatch is drawn without a style attribute" do
    get item_path(@item)
    assert_select "svg.color-swatch[role=img][aria-label=?] circle[fill]", I18n.t("items.color_named", color: "navy")
    assert_select ".color-swatch[style]", 0
  end

  test "a palette chip names its colour and its garment, with no inline style" do
    get ai_palette_path
    assert_response :success
    assert_select ".color-swatch-row .chip", text: /navy\s*, Wool coat/
    assert_select ".color-swatch-row .chip[title]", 0
    assert_select ".color-swatch-row svg.color-swatch[aria-hidden=true]"
    assert_select ".color-swatch-row [style]", 0
  end

  # Eight actions sat in one row. Worn today, joy and Edit stay in reach; AI
  # analysis, tagging, the declutter review and archiving sit under More tools.
  test "the item page leads with its everyday actions and folds the rest away" do
    get item_path(@item)
    nav = "nav.item-detail-actions"
    assert_select "#{nav} > form[action=?]", wear_item_path(@item)
    assert_select "#{nav} > a[href=?]", edit_item_path(@item)
    assert_select "#{nav} > details.wardrobe-more-tools > summary", text: I18n.t("wardrobe.more_tools")
    [ ai_analyze_item_path(@item), ai_tag_item_path(@item), archive_item_path(@item) ].each do |path|
      assert_select "#{nav} > details form[action=?]", path
    end
    assert_select "#{nav} > details a[href=?]", review_declutter_path(@item)
  end
  test "GPS EXIF survives only in the private original, never the display derivative" do
    @item.photos.attach(io: StringIO.new(GPS_JPEG), filename: "gps-coat.jpg", content_type: "image/jpeg")
    original = @item.photos.last
    assert_equal GPS_JPEG, original.download

    original_image = Vips::Image.new_from_buffer(original.download, "")
    assert original_image.get_fields.any? { |field| field.include?("GPSLatitude") },
           "the fixture must contain an embedded GPS latitude tag"

    derivative = original.variant(:thumb).processed
    display_image = Vips::Image.new_from_buffer(derivative.download, "")
    refute display_image.get_fields.any? { |field| field.start_with?("exif-") },
           "public display derivatives must not expose EXIF metadata"
    assert_equal GPS_JPEG, original.download, "variant generation must not rewrite the private original"
  end
end
