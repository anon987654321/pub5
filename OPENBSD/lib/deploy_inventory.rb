# frozen_string_literal: true

require "json"
require "yaml"

module Deploy
  class Inventory
    # Single canonical inventory implementation. MASTER's support path is a
    # require-only adapter into this file, so both toolchains share behavior.
    App = Struct.new(:name, :title, :domain, :port, :deploy_script, :deploy_root, :public, :deploy_order, keyword_init: true) do
      def deploy_group = deploy_root.to_s.split("/", 2).first.to_s.downcase
    end unless defined?(App)

    attr_reader :root

    def initialize(root:)
      @root = root
    end

    def apps
      @apps ||= load_apps
    end

    def app_names
      apps.map(&:name)
    end

    def group_names
      apps.map(&:deploy_group).reject(&:empty?).uniq.sort
    end

    def apps_for_group(name)
      apps.select { |app| app.deploy_group == name.to_s.downcase }
    end

    def target_kind(target)
      value = target.to_s.downcase
      return :all if value == "all"
      return :app if apps.any? { |app| app.name.casecmp?(value) }
      return :group if group_names.include?(value)

      :unknown
    end

    def ordered_apps(group: nil, degraded: false)
      selected = group ? apps_for_group(group) : apps
      selected.each_with_index.sort_by do |(app, index)|
        master_last = degraded && app.deploy_group == "master" ? 1 : 0
        [master_last, app.deploy_order || (10_000 + index), index]
      end.map(&:first)
    end

    def master_apps(path: File.join(root, "OPENBSD", "deploy_inventory.json"))
      data = JSON.parse(File.read(path))
      data.fetch("apps").map { |entry| app_from_json(entry) }
    end

    # One tree's `## <tree>` section of MASTER/data/law/TREE_CONTRACTS.md, or nil.
    # MASTER/web has no README: this section is its human entry, and replaced
    # MASTER/web/CLAUDE.md when the tree contracts were folded (2b168b77f2).
    def tree_contract(tree)
      path = File.join(root, "MASTER", "data", "law", "TREE_CONTRACTS.md")
      return unless File.file?(path)

      File.read(path, encoding: "UTF-8")[/^## #{Regexp.escape(tree)}\n.*?(?=^## |\z)/m]
    end

    private

    REQUIRED_APP_KEYS = %w[domain port deploy_script deploy_root].freeze unless defined?(REQUIRED_APP_KEYS)

    # apps.yml is the fleet's source of truth and is edited by hand, so a missing
    # key has to say which app and which key. It used to raise a bare
    # `KeyError: key not found: "deploy_root"` six frames inside a check, which reads
    # as a broken check rather than an incomplete entry — every check that reads the
    # inventory died the same anonymous way.
    # `deployed: false` marks an app that lives in the tree and runs CI but has no
    # host, port lane or rc.d script yet; the deploy inventory is what vm23 serves.
    def load_apps
      path = File.join(root, "RAILS", "apps.yml")

      data = YAML.safe_load(File.read(path))
      deployable = data.fetch("apps").reject { |_name, meta| meta.is_a?(Hash) && meta["deployed"] == false }
      deployable.map { |name, metadata| app_from_yaml(name, metadata) }
    end

    def app_from_yaml(name, metadata)
      missing = REQUIRED_APP_KEYS.reject { |key| metadata.is_a?(Hash) && metadata.key?(key) }
      unless missing.empty?
        raise KeyError, "RAILS/apps.yml: app #{name.inspect} is missing #{missing.join(', ')} " \
                        "(every app needs #{REQUIRED_APP_KEYS.join(', ')})"
      end

      App.new(
        name:,
        title: metadata["title"],
        domain: metadata.fetch("domain"),
        port: metadata.fetch("port").to_i,
        deploy_script: metadata.fetch("deploy_script"),
        deploy_root: metadata.fetch("deploy_root"),
        public: metadata.fetch("public", false),
        deploy_order: metadata["deploy_order"]&.to_i
      )
    end

    def app_from_json(entry)
      App.new(
        name: entry.fetch("name"),
        title: entry["title"],
        domain: entry.fetch("domain"),
        port: entry.fetch("port").to_i,
        deploy_script: entry["deploy_script"],
        deploy_root: entry["deploy_root"],
        public: entry.fetch("public", false),
        deploy_order: entry["deploy_order"]&.to_i
      )
    end
  end
end
