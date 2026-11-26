# frozen_string_literal: true

module Master
  module Review
    class RepoEcology
      module CoChangeGraph
        CACHE_VERSION = 2

        private

        def build_co_change_graph
          out, status = Master::Io::Exec.capture2e("git", "-C", @root, "log", "--name-only",
                                        "--format=#{COMMIT_SEPARATOR}%P",
                                        "-#{CO_CHANGE_COMMITS}")
          return {} unless status.success?

          count_co_change_pairs(out)
            .then { |pairs| graph_from_counts(pairs) }.transform_values(&:freeze).freeze
        rescue StandardError => e
          @bus&.publish("repo_ecology:co_change_error", error: e.message)
          {}
        end

        def count_co_change_pairs(out)
          pair_counts = Hash.new(0)
          out.split(COMMIT_SEPARATOR).each do |chunk|
            parents, *paths = chunk.lines
            # Root and shallow boundary commits are snapshots, not changes.
            next if parents.to_s.strip.empty?

            files = paths.map(&:strip).reject(&:empty?).uniq.sort
            next if files.size < 2
            files.combination(2) { |a, b| pair_counts[[a, b]] += 1 }
          end
          pair_counts
        end

        def graph_from_counts(pair_counts)
          graph = Hash.new { |h, k| h[k] = {} }
          pair_counts.each do |(a, b), count|
            next if count < CO_CHANGE_MIN_COUNT
            graph[a][b] = count
            graph[b][a] = count
          end
          graph
        end

        def load_or_build_co_change_graph
          # Fetching more history can change a shallow graph without moving HEAD.
          return build_co_change_graph unless complete_history?

          cached = read_co_change_cache
          return cached if cached

          build_co_change_graph.tap { |graph| write_co_change_cache(graph) }
        end

        def complete_history?
          out, status = Master::Io::Exec.capture2e("git", "-C", @root, "rev-parse", "--is-shallow-repository")
          status.success? && out.strip == "false"
        end

        def read_co_change_cache
          path = co_change_cache_path
          return unless File.exist?(path)

          data = YAML.safe_load_file(path, aliases: true)
          return unless data.is_a?(Hash) && data["version"] == CACHE_VERSION && data["head"] == git_head

          thaw_graph(data["graph"] || {})
        rescue StandardError => e
          @bus&.publish("repo_ecology:co_change_cache_error", error: e.message)
          nil
        end

        def write_co_change_cache(graph)
          path = co_change_cache_path
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, { "version" => CACHE_VERSION, "head" => git_head, "graph" => graph }.to_yaml)
        rescue StandardError => e
          @bus&.publish("repo_ecology:co_change_cache_error", error: e.message)
        end

        def thaw_graph(graph)
          graph.each_with_object({}) do |(file, peers), acc|
            acc[file] = (peers || {}).transform_values(&:to_i).freeze
          end.freeze
        end

        def co_change_cache_path
          File.join(@root, CO_CHANGE_CACHE_PATH)
        end

        # Key the cache by the commit itself. .git/HEAD is only the current
        # symbolic ref and normally does not change when a branch advances, so
        # its mtime cannot tell us that git log has new history.
        def git_head
          out, status = Master::Io::Exec.capture2e("git", "-C", @root, "rev-parse", "HEAD")
          raise "co-change graph git HEAD unavailable: #{out}" unless status.success?

          head = out.to_s.strip
          raise "co-change graph git HEAD empty" if head.empty?

          head
        rescue StandardError => e
          raise "co-change graph git HEAD unreadable: #{e.class}: #{e.message}"
        end
      end
    end
  end
end
