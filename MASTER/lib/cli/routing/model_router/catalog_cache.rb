# frozen_string_literal: true

require "json"
require "fileutils"
require "time"
require_relative "../../../io/atomic_write"
require_relative "../../../trace/log"

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
        # and a keyed listing never leaks into a keyless lane. A successful
        # empty listing supersedes older ids; a failed fetch uses the cache.
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
          end

          # Yields to the live fetch and stores its answer; on failure, answers
          # the stored ids for the same endpoint and mode. With no stored ids
          # the error re-raises, so the caller's own rescue keeps its current
          # shape (an empty lane, logged) instead of this cache inventing a
          # second failure vocabulary.
          def ids_for(base, mode)
            live = yield
            raise ArgumentError, "invalid hosted model listing" unless valid_ids?(live)

            store(base, mode, live)
            live
          rescue StandardError => e
            cached = load_for(base, mode)
            raise if cached.nil?

            Master::Ground::Swallow.log(e, context: "ModelRouter::CatalogCache", endpoint: base)
            cached
          end

          def load_for(base, mode)
            row = read_snapshot["endpoints"][key(base, mode)]
            ids = row["ids"] if row.is_a?(Hash)
            ids if valid_ids?(ids)
          end

          def store(base, mode, ids)
            return false unless valid_ids?(ids)

            FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
            lock_path = "#{path}.lock"
            Master::Trace::Log.with_private_file(lock_path, File::RDWR | File::CREAT, mode: 0o600, label: "catalogue lock") do |lock|
              raise IOError, "catalogue lock unavailable" unless lock.flock(File::LOCK_EX)

              Master::Trace::Log.verify_file_identity!(lock, lock_path, "catalogue lock")
              data = read_snapshot
              row = data["endpoints"][key(base, mode)]
              return false if row.is_a?(Hash) && row["ids"] == ids

              data["endpoints"][key(base, mode)] = { "ids" => ids, "stored_at" => Time.now.utc.iso8601 }
              Master::Io::AtomicWrite.write_atomic(path, JSON.generate(data), mode: 0o600)
            end
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

          def valid_ids?(ids)
            ids.is_a?(Array) && ids.all? { |id| id.is_a?(String) && !id.strip.empty? }
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
