# frozen_string_literal: true

module Shared
  # Locates master/contracts for the repo checkout and for the deploy copy-tree,
  # where shared sits beside app/ under /home/<app> and master is outside it.
  # PUB5_ROOT (exported by rc.d and vps_ci.sh) names the checkout that holds
  # MASTER. A task started as the app user without it (db:prepare and the asset
  # precompile in vps-deploy) has no PUB5_ROOT, and the repo-relative walk lands
  # on /home/MASTER, which killed the first deploy that reached the migration and
  # left the app stopped. So the root is the first candidate that holds
  # master/contracts: PUB5_ROOT, the repo root four levels above this file, then
  # the box's own checkout.
  module Contracts
    CHECKOUT_ON_BOX = "/home/dev/pub4"

    module_function

    def root
      candidates = [ENV["PUB5_ROOT"].to_s.strip, File.expand_path("../../../..", __dir__), CHECKOUT_ON_BOX].reject(&:empty?)
      candidates.find { |path| File.directory?(File.join(path, "master", "contracts")) } || candidates.first
    end

    def dir
      File.join(root, "master", "contracts")
    end

    # master/tools holds the plain-Ruby audits the shared test examples run.
    def tool_path(name)
      File.join(root, "master", "tools", name.to_s)
    end

    def require_contract(name)
      require File.join(dir, name.to_s)
    end
  end
end
