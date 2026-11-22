# frozen_string_literal: true

require "tmpdir"
require_relative "test_helper"

# /fix runs from MASTER, and a repair to a file beside it (RAILS, OPENBSD) must still be seen,
# snapshotted and committed.
class TestFixRepoScope < Minitest::Test
  # Records commits; reports the paths it was given as changed.
  class FakeGit
    attr_reader :commits

    def initialize(changed)
      @changed = changed
      @commits = []
    end

    def changed_paths = @changed
    def commit(message, paths:) = @commits << [message, paths]
  end

  # A committer rooted in <repo>/MASTER whose repository git is a fake.
  class Scoped < Master::Fix::FixLoop::Committer
    def initialize(repo:, master_git:, repo_git:)
      super(git: master_git, root: File.join(repo, "MASTER"))
      @repo = repo
      @fake_repo_git = repo_git
    end

    private

    def repo_root = @repo
    def repo_git = @fake_repo_git
  end

  def scoped(repo, inside: [], everywhere: [])
    repo_git = FakeGit.new(everywhere)
    [Scoped.new(repo:, master_git: FakeGit.new(inside), repo_git:), repo_git]
  end

  class ProductionScoped < Master::Fix::FixLoop::Committer
    def initialize(root:, repository:)
      super(git: FakeGit.new([]), root:)
      @repository = repository
    end

    private

    def repo_root = @repository
  end

  def test_external_checkout_with_a_shared_prefix_is_not_a_sibling
    Dir.mktmpdir do |parent|
      repository = File.join(parent, "pub5")
      external = File.join(parent, "pub5-external", "MASTER")
      FileUtils.mkdir_p([repository, external])
      committer = ProductionScoped.new(root: external, repository:)

      refute committer.send(:beside_repo?)
      assert_nil committer.send(:repo_git)
    end
  end

  def test_symlinked_workspace_cannot_borrow_repository_git
    Dir.mktmpdir do |parent|
      repository = File.join(parent, "pub5")
      external = File.join(parent, "external", "MASTER")
      FileUtils.mkdir_p([repository, external])
      link = File.join(repository, "MASTER")
      File.symlink(external, link)
      committer = ProductionScoped.new(root: link, repository:)

      refute committer.send(:beside_repo?)
      assert_raises(ArgumentError) { committer.send(:repo_relative, "../RAILS/app.rb") }
    end
  end

  def test_changes_beside_master_are_named_relative_to_it
    committer, = scoped("/repo", inside: ["lib/a.rb"], everywhere: ["MASTER/lib/a.rb", "RAILS/amber/app/b.rb"])

    assert_equal ["lib/a.rb", "../RAILS/amber/app/b.rb"], committer.changed_everywhere
  end

  def test_a_commit_holding_a_rails_file_goes_through_the_repository
    committer, repo_git = scoped("/repo")

    committer.commit_scoped("fix", paths: ["lib/a.rb", "../RAILS/amber/app/b.rb"])

    assert_equal [["fix", ["MASTER/lib/a.rb", "RAILS/amber/app/b.rb"]]], repo_git.commits
  end

  # A transaction rooted in <repo>/MASTER inside a temporary repository.
  class BesideTransaction < Master::Fix::Transaction
    private

    def outer_root = File.dirname(File.expand_path(@root))
  end

  def test_the_transaction_snapshots_and_restores_a_file_beside_its_root
    Dir.mktmpdir do |repo|
      master = File.join(repo, "MASTER").tap { |dir| FileUtils.mkdir_p(dir) }
      rails = File.join(repo, "RAILS", "b.rb").tap { |path| FileUtils.mkdir_p(File.dirname(path)) }
      File.write(rails, "before")
      tx = BesideTransaction.new(root: master, paths: [rails], id: "beside").begin!
      File.write(rails, "after")
      tx.observe!

      assert tx.rollback!.ok?
      assert_equal "before", File.read(rails)
    end
  end
end
