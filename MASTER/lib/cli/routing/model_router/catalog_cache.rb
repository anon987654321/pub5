# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module Master
  module CLI
    module Routing
      class ModelRouter
        # Last known good <base>/models listings, persisted so an offline
        # start degrades to the previous catalogue instead of an empty hosted
        # pool. The router rebuilds its index on every construction and a
        # listing fetch that fails today answers nothing (the hosted_ids
        # rescue); this cache turns that empty answer into the ids the
        # endpoint listed the last time it answered.
        #
        # Rows are stored already-filtered, keyed by endpoint and mode, so a
        # cached keyless listing can never widen what the keyless rule admits
        # and a keyed listing never leaks into a keyless lane. Only non-empty
        # listings are stored: an empty live answer is the failure shape the
        # cache exists to paper over, not a fact worth keeping.
        module CatalogCache
          module_function

          def path
            @path ||= File.expand_path(
              ENV.fetch(
                "MASTER_CATALOG_CACHE",
                File.join(Master::ROOT, "runtime", "catalog", "hosted_models.json"),
              )
            )
          end

          def path=(value)
            @path = value
            @snapshot = nil
          end

          # Yields to the live fetch and stores its answer; on failure, answers
          # the stored ids for the same endpoint and mode. With no stored ids
          # the error re-raises, so the caller's own rescue keeps its current
          # shape (an empty lane, logged) instead of this cache inventing a
          # second failure vocabulary.
          def ids_for(base, mode)
            live = yield
            store(base, mode, live)
            live
          rescue StandardError => e
            cached = load_for(base, mode)
            raise if cached.nil?

            Master::Ground::Swallow.log(e, context: "ModelRouter::CatalogCache", endpoint: base)
            cached
          end

          def load_for(base, mode)
            snapshot.dig("endpoints", key(base, mode), "ids")
          end

          def store(base, mode, ids)
            ids = Array(ids).map(&:to_s)
            return false if ids.empty? || load_for(base, mode) == ids

            snapshot["endpoints"][key(base, mode)] = {
              "ids" => ids,
              "stored_at" => Time.now.utc.iso8601,
            }
            FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
            File.write(path, JSON.generate(snapshot), perm: 0o600)
            true
          rescue StandardError => e
            # A cache write must never cost a turn: the live answer is already
            # in hand, the snapshot is a courtesy to the next offline start.
            Master::Ground::Swallow.log(e, context: "ModelRouter::CatalogCache.store", path:)
            false
          end

          def key(base, mode)
            "#{base}|#{mode}"
          end

          def snapshot
            @snapshot ||= read_snapshot
          end

          def read_snapshot
            return { "version" => 1, "endpoints" => {} } unless File.file?(path)

            parsed = JSON.parse(File.read(path))
            parsed.is_a?(Hash) && parsed["endpoints"].is_a?(Hash) ? parsed : { "version" => 1, "endpoints" => {} }
          rescue JSON::ParserError, EncodingError, SystemCallError => e
            Master::Ground::Swallow.log(e, context: "ModelRouter::CatalogCache.read", path:)
            { "version" => 1, "endpoints" => {} }
          end
        end
      end
    end
  end
end
