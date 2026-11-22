# frozen_string_literal: true

require "test_helper"

# "Last import: %{status}" was filled with the raw ImportRun status, so an
# nb reader got "Siste import: succeeded".
class ImportStatusLabelTest < ActionDispatch::IntegrationTest
  test "the index warns when its last refresh had names and versions only" do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    Port.create!(platform:, category:, name: "git", version: "2.45", pkgpath: "devel/git")
    ImportRun.create!(
      platform:, status: "succeeded", started_at: 1.hour.ago, ports_count: 1,
      source_revision: "https://cdn.openbsd.org/pub/OpenBSD/7.8/packages/amd64/index.txt"
    )

    get root_url(locale: "nb")
    assert_response :success
    assert_includes response.body, I18n.t("ports.package_index_only", locale: :nb)
  end

  test "a full ports-tree refresh does not show the package-index warning" do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    Port.create!(platform:, category:, name: "git", version: "2.45", pkgpath: "devel/git")
    ImportRun.create!(
      platform:, status: "succeeded", started_at: 1.hour.ago, ports_count: 1,
      source_revision: "/usr/ports"
    )

    get root_url
    assert_response :success
    assert_not_includes response.body, I18n.t("ports.package_index_only")
  end

  test "the last import names its status in the reader's language" do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    Port.create!(platform:, category:, name: "git", version: "2.45", pkgpath: "devel/git")
    ImportRun.create!(platform:, status: "succeeded", started_at: 1.hour.ago, ports_count: 1)

    get root_url(locale: "nb")
    assert_response :success
    assert_includes response.body, I18n.t("ports.import_status.succeeded", locale: :nb)
    assert_no_match(/import: succeeded/i, response.body)
  end
end
