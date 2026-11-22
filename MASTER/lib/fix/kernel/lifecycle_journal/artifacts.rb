# frozen_string_literal: true

module Master
  module Fix
    class Kernel
      # Private-artifact safety on the run journal: TOCTOU-checked reads of
      # state-root files, directory preparation and slot refusal for artifact
      # publication, receipt-path naming, and JSON payload normalization.
      class LifecycleJournal
        private

        def prepare_artifact_directory!(directory)
          root = File.expand_path(@state_root)
          full_directory = File.expand_path(directory)
          expected_prefix = "#{root}#{File::SEPARATOR}"
          unless full_directory.start_with?(expected_prefix)
            raise IOError, "artifact directory escapes persistent fix state"
          end

          ensure_state_directory!
          FileUtils.mkdir_p(full_directory, mode: 0o700)
          directory_stat = File.lstat(full_directory)
          unless directory_stat.directory? && !directory_stat.symlink?
            raise IOError, "artifact path is not a real directory"
          end
          File.chmod(0o700, full_directory) unless (directory_stat.mode & 0o7777) == 0o700
          final_stat = File.lstat(full_directory)
          raise IOError, "artifact directory permissions are not private" unless
            final_stat.directory? && !final_stat.symlink? && (final_stat.mode & 0o077).zero?
          full_directory
        rescue SystemCallError => error
          raise IOError, "cannot prepare artifact directory safely: #{error.class}: #{error.message}"
        end

        def refuse_unsafe_artifact_slot!(path, label:)
          parent = File.dirname(File.expand_path(path))
          unless parent == File.expand_path(File.join(@state_root, ASSESSMENT_DIR)) ||
                 parent == File.expand_path(File.join(@state_root, ARCHITECTURE_DIR))
            raise IOError, "#{label} path is outside its dedicated artifact directory"
          end

          return unless File.exist?(path) || File.symlink?(path)

          stat = File.lstat(path)
          unless stat.file? && !stat.symlink? && stat.nlink == 1
            raise IOError, "refusing symlinked, hard-linked or non-regular #{label}"
          end
        rescue SystemCallError => error
          raise IOError, "cannot inspect #{label} path safely: #{error.class}: #{error.message}"
        end

        def read_private_artifact(path, label:)
          root = File.expand_path(@state_root)
          expanded = File.expand_path(path)
          root_prefix = "#{root}#{File::SEPARATOR}"
          unless expanded.start_with?(root_prefix)
            raise ArtifactReadError.new("artifact_path_unsafe", "#{label} escapes persistent fix state")
          end

          verify_artifact_root!(root, label)
          verify_artifact_parents!(root, expanded, label)
          verify_artifact_entry!(expanded, label)
          read_stable_artifact(expanded, label)
        rescue ArtifactReadError
          raise
        rescue SystemCallError => error
          raise ArtifactReadError.new("artifact_read_failed",
                                      "#{label} cannot be read safely: #{error.class}: #{error.message}")
        end

        def verify_artifact_root!(root, label)
          root_stat = File.lstat(root)
          unless root_stat.directory? && !root_stat.symlink?
            raise ArtifactReadError.new("artifact_directory_unsafe", "#{label} state root is not a real directory")
          end
          return unless (root_stat.mode & 0o022).positive?

          raise ArtifactReadError.new("artifact_directory_unsafe", "#{label} state root is group/world writable")
        end

        def verify_artifact_parents!(root, expanded, label)
          relative_parent = File.dirname(expanded).delete_prefix(root + File::SEPARATOR)
          cursor = root
          relative_parent.split(File::SEPARATOR).each do |component|
            cursor = File.join(cursor, component)
            stat = File.lstat(cursor)
            unless stat.directory? && !stat.symlink?
              raise ArtifactReadError.new("artifact_directory_unsafe", "#{label} parent is not a real directory")
            end
            if (stat.mode & 0o022).positive?
              raise ArtifactReadError.new("artifact_directory_unsafe", "#{label} state directory is group/world writable")
            end
            next unless cursor == File.dirname(expanded) && (stat.mode & 0o077).positive?

            raise ArtifactReadError.new("artifact_directory_permissions_insecure",
                                        "#{label} directory permissions are not private",
                                        "mode" => format("%04o", stat.mode & 0o777))
          end
        end

        def verify_artifact_entry!(expanded, label)
          unless File.exist?(expanded) || File.symlink?(expanded)
            raise ArtifactReadError.new("artifact_unavailable", "#{label} is missing")
          end

          before = File.lstat(expanded)
          unless before.file? && !before.symlink? && before.nlink == 1
            raise ArtifactReadError.new("artifact_path_unsafe", "#{label} must be a singly linked regular file")
          end
          return unless (before.mode & 0o077).positive?

          raise ArtifactReadError.new("artifact_permissions_insecure", "#{label} permissions are not private",
                                      "mode" => format("%04o", before.mode & 0o777))
        end

        def read_stable_artifact(expanded, label)
          flags = File::RDONLY
          flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
          File.open(expanded, flags) do |file|
            opened = file.stat
            current = File.lstat(expanded)
            unless current.file? && !current.symlink? && current.nlink == 1 &&
                   current.dev == opened.dev && current.ino == opened.ino
              raise ArtifactReadError.new("artifact_path_changed", "#{label} path changed while opening")
            end

            payload = file.read
            after = File.lstat(expanded)
            unless after.file? && !after.symlink? && after.nlink == 1 &&
                   after.dev == opened.dev && after.ino == opened.ino &&
                   after.size == opened.size && after.mtime == opened.mtime && after.ctime == opened.ctime
              raise ArtifactReadError.new("artifact_changed_during_read", "#{label} changed while reading")
            end
            verify_artifact_payload_encoding!(payload, label)
            payload
          end
        end

        def verify_artifact_payload_encoding!(payload, label)
          payload.force_encoding(Encoding::UTF_8)
          return if payload.valid_encoding?

          raise ArtifactReadError.new("artifact_invalid_encoding", "#{label} contains invalid UTF-8")
        end

        # Receipt paths retain the historical workspace-relative .master
        # namespace even when the bytes live outside the checkout.
        def state_relative(path)
          full = File.expand_path(path.to_s)
          root = File.expand_path(@state_root)
          return ".master" if full == root
          return path.to_s unless full.start_with?(root + File::SEPARATOR)

          ".master/#{full.delete_prefix(root + File::SEPARATOR).tr(File::SEPARATOR, "/")}"
        rescue ArgumentError
          nil
        end

        # Report payloads may carry model-shaped values (symbols, floats, objects);
        # the artifact and journal only store JSON-safe primitives.
        def json_safe_value(value)
          case value
          when NilClass, TrueClass, FalseClass, String, Integer
            value
          when Float
            value.finite? ? value : value.to_s
          when Symbol
            value.to_s
          when Array
            value.map { |entry| json_safe_value(entry) }
          when Hash
            value.each_with_object({}) do |(key, entry), normalized|
              normalized[key.to_s] = json_safe_value(entry)
            end
          else
            value.respond_to?(:to_h) ? json_safe_value(value.to_h) : value.to_s
          end
        end
      end
    end
  end
end
