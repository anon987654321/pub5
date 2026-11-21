# frozen_string_literal: true

require "digest"
require "find"
require "ipaddr"
require "json"
require "set"
require "tempfile"
require "net/http"
require "timeout"
require "uri"
require_relative "../../lib/io/ssrf_guard"

module Master
  module Plugins
    # Soulseek discovery and collection-gap tools backed by an operator-owned
    # slskd daemon. Queueing is one explicitly selected, rights-cleared file.
    class Soulseek < Master::Plugin::Base
      Error = Master::Plugin::Error
      PolicyError = Master::Plugin::PolicyError

      AUDIO_EXTENSIONS = %w[
        .aac .aiff .alac .ape .flac .m4a .m4p .mp3 .mpc .oga .ogg .opus .wav .wma .wv
      ].freeze
      MAX_QUERY_BYTES = 240
      MAX_RESULTS = 100
      MAX_LIBRARY_FILES = 200_000
      MAX_HASH_FILES = 50_000
      MAX_SMALL_AUDIO_BYTES = 64 * 1024
      LOSSLESS_EXTENSIONS = %w[.aiff .alac .ape .flac .wav .wv].freeze
      LOSSY_EXTENSIONS = %w[.aac .mp3 .mpc .oga .ogg .opus .wma].freeze
      AMBIGUOUS_AUDIO_EXTENSIONS = %w[.m4a .m4p].freeze
      MAX_MANIFEST_BYTES = 16 * 1024 * 1024
      MAX_MANIFEST_LINES = 500_000
      MAX_MANIFEST_PATHS = 8
      MAX_RESPONSE_BYTES = 2 * 1024 * 1024
      REQUEST_TIMEOUT = 12
      SEARCH_ID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i.freeze

      def call(action:, query: nil, search_id: nil, path: nil, queries: nil,
               username: nil, filename: nil, size: nil, consent: false,
               rights_basis: nil, paths: nil, output_path: nil, overwrite: false,
               mode: "candidates", **_options)
        law_admission!
        case action.to_s
        when "status" then status
        when "search" then search(query)
        when "results" then search_results(search_id)
        when "downloads" then downloads
        when "library" then library(path)
        when "quality" then quality(path)
        when "gaps" then gaps(path, queries)
        when "manifest"
          require_policy!("manifest_import", expected: "explicit_path_read_only")
          manifest_audit(paths || path)
        when "catalog"
          catalog(path, output_path:, overwrite:, consent:)
        when "duplicates"
          duplicates(path, mode:)
        when "queue"
          queue_file(search_id:, username:, filename:, size:, consent:, rights_basis:)
        else
          raise PolicyError, "soulseek: unknown action #{action.inspect}"
        end
      end

      private

      def status
        return status_without_key unless api_key

        state = api_request(:get, "server")
        state = {} unless state.is_a?(Hash)
        {
          plugin: manifest.id,
          configured: true,
          connected: server_connected?(state),
          endpoint: endpoint_label,
          server: state.select { |key, _| %w[state isConnected connected username listenPort].include?(key) },
          capabilities: %w[search results downloads library gaps queue],
          acquisition: "one explicitly selected file per invocation",
          rights_basis_required: Array(policy.fetch("rights_basis_required")),
        }
      rescue Error, PolicyError, IOError, SocketError, SystemCallError, Timeout::Error => e
        {
          plugin: manifest.id,
          configured: true,
          connected: false,
          endpoint: endpoint_label,
          error: e.class.name.split("::").last,
          required_env: %w[MASTER_SLSKD_URL MASTER_SLSKD_API_KEY],
        }
      end

      def status_without_key
        {
          plugin: manifest.id,
          configured: false,
          connected: false,
          endpoint: endpoint_label,
          required_env: %w[MASTER_SLSKD_URL MASTER_SLSKD_API_KEY],
          note: "Set the API key in the process environment; MASTER never stores it.",
        }
      end

      def server_connected?(state)
        return state["isConnected"] unless state["isConnected"].nil?
        return state["connected"] unless state["connected"].nil?

        state["state"].to_s.casecmp?("connected")
      end

      def search(query)
        text = clean_query(query)
        response = api_request(:post, "searches", {
          searchText: text, responseLimit: 50, fileLimit: 500,
          searchTimeout: 8, filterResponses: true
        })
        id = response["id"].to_s
        raise Error, "slskd returned no search ID" unless id.match?(SEARCH_ID)

        {
          action: "search", search_id: id, query: text, state: response["state"],
          note: "Search submitted. Call results with this search ID after peers respond."
        }
      end

      def search_results(search_id)
        id = clean_search_id(search_id)
        responses = Array(api_request(:get, "searches/#{id}/responses"))
        files = responses.flat_map do |response|
          next [] unless response.is_a?(Hash)

          Array(response["files"]).filter_map do |file|
            next unless file.is_a?(Hash)
            name = file["filename"].to_s
            next unless audio_file?(name)

            {
              username: response["username"].to_s,
              filename: name,
              size: file["size"].to_i,
              bitrate: file["bitRate"],
              sample_rate: file["sampleRate"],
              bit_depth: file["bitDepth"],
              free_slot: response["hasFreeUploadSlot"] == true,
              queue_length: response["queueLength"],
              upload_speed: response["uploadSpeed"],
            }
          end
        end

        {
          action: "results", search_id: id, files: files.length,
          results: files.first(MAX_RESULTS),
          note: "Only unlocked audio files are listed. Peer metadata is unverified."
        }
      end

      def downloads
        rows = api_request(:get, "transfers/downloads")
        rows = [] unless rows.is_a?(Array)
        {
          action: "downloads", count: rows.length,
          transfers: rows.first(50).filter_map do |row|
            next unless row.is_a?(Hash)
            row.select do |key, _|
              %w[username filename state percentComplete bytesTransferred size startedAt endedAt].include?(key)
            end
          end
        }
      end

      def library(path)
        inventory = scan_library(path)
        {
          action: "library", path: inventory[:path], tracks: inventory[:tracks],
          bytes: inventory[:bytes], extensions: inventory[:extensions],
          truncated: inventory[:truncated],
          sample: inventory[:files].first(12).map { |file| file[:relative_path] },
          note: "Read-only filename and file-size inventory; no audio is opened or changed."
        }
      end

      def quality(path)
        require_policy!("quality_check", expected: "explicit_path_read_only")
        inventory = scan_library(path)
        files = inventory[:files]
        empty = files.select { |file| file[:size].zero? }
        small = files.select { |file| file[:size].positive? && file[:size] <= MAX_SMALL_AUDIO_BYTES }
        format_classes = {
          lossless: files.count { |file| LOSSLESS_EXTENSIONS.include?(file[:extension]) },
          lossy: files.count { |file| LOSSY_EXTENSIONS.include?(file[:extension]) },
          ambiguous_container: files.count { |file| AMBIGUOUS_AUDIO_EXTENSIONS.include?(file[:extension]) },
          unclassified: files.count do |file|
            !LOSSLESS_EXTENSIONS.include?(file[:extension]) &&
              !LOSSY_EXTENSIONS.include?(file[:extension]) &&
              !AMBIGUOUS_AUDIO_EXTENSIONS.include?(file[:extension])
          end
        }
        {
          action: "quality",
          tracks_scanned: inventory[:tracks],
          formats: inventory[:extensions],
          format_classes:,
          empty_files: empty.length,
          unusually_small_files: small.length,
          review: (empty + small).first(200).map do |file|
            { path: file[:relative_path], size: file[:size], reason: file[:size].zero? ? "empty_file" : "very_small_file" }
          end,
          review_list_truncated: empty.length + small.length > 200,
          truncated: inventory[:truncated],
          note: "Structural triage only. Small files may be short clips or intentional samples; file extension does not establish bitrate or fidelity. No audio was decoded or changed."
        }
      end

      def gaps(path, queries)
        requested = Array(queries)
        raise PolicyError, "soulseek: gaps needs 1–100 album or artist queries" unless requested.any? && requested.length <= 100

        inventory = scan_library(path)
        candidates = inventory[:files].map { |file| normalize_title(file[:relative_path]) }
        present, missing = requested.map { |item| clean_query(item) }.uniq.partition do |query|
          query_matches_library?(query, candidates)
        end
        {
          action: "gaps", path: inventory[:path],
          checked: present.length + missing.length, present:, missing:,
          library_tracks_scanned: inventory[:tracks], truncated: inventory[:truncated],
          note: "Filename heuristic only; confirm editions and recordings before acquisition."
        }
      end

      def manifest_audit(paths)
        values = Array(paths).flatten(1).map { |value| value.to_s.strip }.reject(&:empty?)
        unless values.any? && values.length <= MAX_MANIFEST_PATHS
          raise PolicyError, "soulseek: manifest needs 1–#{MAX_MANIFEST_PATHS} explicit export paths"
        end

        sources = values.map { |value| audit_manifest(value) }
        comparisons = sources.combination(2).map do |left, right|
          shared = left[:paths] & right[:paths]
          shared_audio = left[:audio_paths] & right[:audio_paths]
          {
            sources: [left[:label], right[:label]],
            exact_shared_paths: shared.length,
            exact_shared_audio_paths: shared_audio.length,
            examples: shared.to_a.first(10)
          }
        end
        {
          action: "manifest",
          sources: sources.map { |source| source.reject { |key, _| %i[paths audio_paths].include?(key) } },
          comparisons:,
          note: "Path overlap proves only that the same relative path appears in both exports. Different paths do not prove different audio; filenames do not verify tags, recordings, editions or rights."
        }
      end

      def audit_manifest(value)
        path = File.realpath(File.expand_path(value))
        stat = File.stat(path)
        raise PolicyError, "soulseek: manifest path is not a regular file" unless stat.file?
        raise PolicyError, "soulseek: manifest exceeds #{MAX_MANIFEST_BYTES} bytes" if stat.size > MAX_MANIFEST_BYTES

        lines = File.readlines(path, chomp: true, encoding: "UTF-8")
        raise PolicyError, "soulseek: manifest exceeds #{MAX_MANIFEST_LINES} lines" if lines.length > MAX_MANIFEST_LINES

        paths = Set.new
        audio_paths = Set.new
        directories = Set.new
        extensions = Hash.new(0)
        duplicate_entries = 0
        entries = 0

        lines.each do |line|
          entry = line.to_s.strip
          next if entry.empty? || entry.start_with?("#") || entry.start_with?(0x60.chr * 3)

          entry = entry.tr("\\", "/")
          directory = entry.end_with?("/")
          relative = directory ? entry.sub(%r{/+\z}, "") : entry
          next unless relative.include?("/")
          next if relative.start_with?("/", "~") || relative.match?(/\A[A-Za-z]:/)
          segments = relative.split("/")
          next if segments.any? { |segment| segment.empty? || segment == "." || segment == ".." }
          next if relative.match?(/[[:cntrl:]]/)

          entries += 1
          if directory
            directories << relative
            next
          end

          duplicate_entries += 1 unless paths.add?(relative)
          ext = File.extname(relative).downcase
          extensions[ext.empty? ? "[none]" : ext] += 1
          audio_paths << relative if AUDIO_EXTENSIONS.include?(ext)
        end

        categories = audio_paths.group_by { |relative| relative.split("/").first }
        {
          label: File.basename(path),
          source_bytes: stat.size,
          entries:,
          files: paths.length,
          directories: directories.length,
          audio_files: audio_paths.length,
          album_folders_with_audio: audio_paths.map { |relative| File.dirname(relative) }.uniq.length,
          duplicate_entries:,
          extensions: extensions.sort.to_h,
          top_categories: categories.sort_by { |_, items| -items.length }.first(20).to_h.transform_values(&:length),
          paths:,
          audio_paths:
        }
      rescue Errno::ENOENT, Errno::ENOTDIR, Errno::EACCES, IOError, EncodingError
        raise PolicyError, "soulseek: manifest does not exist, cannot be read, or is not valid UTF-8"
      end

      def catalog(path, output_path:, overwrite:, consent:)
        require_policy!("catalogue_build", expected: "explicit_path_read_only")
        inventory = scan_library(path)
        albums = inventory[:files].group_by { |file| File.dirname(file[:relative_path]) }
        album_rows = albums.sort_by { |directory, _| directory }.map do |directory, files|
          label = directory == "." ? File.basename(inventory[:path]) : File.basename(directory)
          {
            directory:,
            release_hint: label.tr("_", " ").gsub(/\s+/, " ").strip,
            year_hint: label[/\b(?:19|20)\d{2}\b/],
            track_count: files.length,
            audio_bytes: files.sum { |file| file[:size] },
            formats: files.group_by { |file| file[:extension] }.transform_values(&:length).sort.to_h,
            tracks: files.sort_by { |file| file[:relative_path] }.map do |file|
              track_hint(file)
            end
          }
        end

        document = {
          schema: "master.music-catalog.v1",
          generated_at: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
          source: {
            root: inventory[:path],
            scan: "read_only_filesystem_inventory",
            embedded_audio_metadata_read: false
          },
          summary: {
            audio_files: inventory[:tracks],
            album_folders: album_rows.length,
            total_bytes: inventory[:bytes],
            formats: inventory[:extensions],
            truncated: inventory[:truncated]
          },
          albums: album_rows
        }

        exported = nil
        unless output_path.to_s.strip.empty?
          require_consent!(consent)
          require_policy!("catalogue_export", expected: "explicit_path_with_consent")
          exported = write_catalogue(document, output_path, inventory[:path], overwrite:)
        end

        {
          action: "catalog", path: inventory[:path],
          tracks: inventory[:tracks], albums: album_rows.length,
          bytes: inventory[:bytes], formats: inventory[:extensions],
          truncated: inventory[:truncated], export_path: exported,
          sample: album_rows.first(12).map do |album|
            { directory: album[:directory], release_hint: album[:release_hint], track_count: album[:track_count] }
          end,
          note: "Release and track labels are filename/folder hints, not verified metadata. Embedded tags and audio content were not read; originals were not changed."
        }
      end

      def track_hint(file)
        basename = File.basename(file[:relative_path], File.extname(file[:relative_path]))
        match = basename.match(/\A(?:(?:cd|disc)\s*\d+[._ -]*)?(?<number>\d{1,3})[._ -]+(?<title>.+)\z/i)
        {
          filename: File.basename(file[:relative_path]),
          title_hint: (match ? match[:title] : basename).tr("_", " ").gsub(/\s+/, " ").strip,
          track_number_hint: match && match[:number].to_i,
          size: file[:size],
          format: file[:extension]
        }
      end

      def write_catalogue(document, output_path, library_root, overwrite:)
        expanded = File.expand_path(output_path.to_s)
        parent = File.realpath(File.dirname(expanded))
        target = File.join(parent, File.basename(expanded))
        inside_library = target == library_root || target.start_with?("#{library_root}#{File::SEPARATOR}")
        raise PolicyError, "soulseek: catalogue export must be outside the music library" if inside_library
        raise PolicyError, "soulseek: refusing a symlink export target" if File.symlink?(target)
        raise PolicyError, "soulseek: export target is a directory" if File.directory?(target)
        if File.exist?(target) && !overwrite
          raise PolicyError, "soulseek: export exists; set overwrite: true with consent to replace it"
        end

        temporary = Tempfile.new([".master-music-catalog-", ".json"], parent)
        begin
          temporary.write(JSON.pretty_generate(document))
          temporary.write("\n")
          temporary.flush
          temporary.fsync
          temporary.close
          File.rename(temporary.path, target)
        ensure
          temporary.close!
        end
        target
      rescue Errno::ENOENT, Errno::EACCES, Errno::EISDIR, Errno::ENOTDIR, IOError, SystemCallError
        raise PolicyError, "soulseek: catalogue export path is not writable or its parent directory does not exist"
      end

      def duplicates(path, mode:)
        require_policy!("duplicate_detection", expected: "read_only")
        inventory = scan_library(path)
        @duplicate_scan_skipped = 0
        selected_mode = mode.to_s
        groups = case selected_mode
                 when "candidates"
                   candidate_duplicate_groups(inventory[:files])
                 when "sha256"
                   require_policy!("sha256_duplicates", expected: true)
                   exact_duplicate_groups(inventory[:files])
                 else
                   raise PolicyError, "soulseek: duplicate mode must be candidates or sha256"
                 end
        rows = groups.map do |signature, files|
          size = files.first[:size]
          {
            classification: selected_mode == "sha256" ? "exact_content_match" : "possible_same_name_and_size",
            signature:,
            copies: files.length,
            bytes_per_copy: size,
            reclaimable_bytes_if_one_copy_were_removed: size * (files.length - 1),
            files: files.map { |file| { path: file[:relative_path], size: file[:size] } }
          }
        end
        {
          action: "duplicates", mode: selected_mode,
          tracks_scanned: inventory[:tracks], groups: rows.length,
          files_in_groups: rows.sum { |row| row[:copies] },
          reclaimable_bytes_if_deduplicated: rows.sum { |row| row[:reclaimable_bytes_if_one_copy_were_removed] },
          skipped_unreadable_or_changed: @duplicate_scan_skipped.to_i,
          duplicates: rows.first(500),
          truncated: rows.length > 500,
          note: selected_mode == "sha256" ?
            "Groups are SHA-256 byte-identical files. No file was changed or deleted." :
            "Candidates share normalized basename and byte size only; these are not confirmed duplicates. Use mode sha256 to verify file contents."
        }
      end

      def candidate_duplicate_groups(files)
        groups = Hash.new { |hash, key| hash[key] = [] }
        files.each do |file|
          basename = File.basename(file[:relative_path], File.extname(file[:relative_path]))
          groups[[file[:size], normalize_title(basename)]] << file
        end
        groups.select { |_, matches| matches.length > 1 }
      end

      def exact_duplicate_groups(files)
        raise PolicyError, "soulseek: refusing to hash more than #{MAX_HASH_FILES} tracks in one action" if files.length > MAX_HASH_FILES

        @duplicate_scan_skipped = 0
        groups = Hash.new { |hash, key| hash[key] = [] }
        files.each do |file|
          before = File.lstat(file[:absolute_path])
          unless before.file? && !before.symlink? && before.size == file[:size]
            @duplicate_scan_skipped += 1
            next
          end

          digest = Digest::SHA256.file(file[:absolute_path]).hexdigest
          after = File.lstat(file[:absolute_path])
          stable = after.file? && !after.symlink? &&
                   [before.dev, before.ino, before.size, before.mtime] ==
                     [after.dev, after.ino, after.size, after.mtime]
          if stable
            groups[digest] << file
          else
            @duplicate_scan_skipped += 1
          end
        rescue Errno::ENOENT, Errno::EACCES, IOError
          @duplicate_scan_skipped += 1
        end
        groups.select { |_, matches| matches.length > 1 }
      end

      def queue_file(search_id:, username:, filename:, size:, consent:, rights_basis:)
        require_consent!(consent)
        require_policy!("bulk_download", expected: false)
        admitted = Array(policy.fetch("rights_basis_required")).map(&:to_s)
        basis = rights_basis.to_s
        raise PolicyError, "soulseek: rights_basis must be one of #{admitted.join(', ')}" unless admitted.include?(basis)

        id = clean_search_id(search_id)
        peer = clean_username(username)
        remote_file = clean_remote_filename(filename)
        bytes = Integer(size)
        raise PolicyError, "soulseek: file size must be positive" unless bytes.positive?

        found = Array(api_request(:get, "searches/#{id}/responses")).any? do |response|
          response.is_a?(Hash) && response["username"].to_s == peer &&
            Array(response["files"]).any? do |file|
              file.is_a?(Hash) && file["filename"].to_s == remote_file && file["size"].to_i == bytes
            end
        end
        raise PolicyError, "soulseek: selected file is not an unlocked result in that search" unless found

        response = api_request(:post, "transfers/downloads/batches", {
          username: peer, searchId: id,
          files: [{ filename: remote_file, size: bytes }]
        })
        {
          action: "queue", submitted: true, username: peer, filename: remote_file,
          size: bytes, rights_basis: basis, batch_id: response.dig("batch", "id"),
          note: "slskd accepted the single-file batch. Rights basis is the operator's attestation, not independent verification."
        }
      rescue ArgumentError, TypeError
        raise PolicyError, "soulseek: size must be an integer"
      end

      def clean_query(value)
        text = value.to_s.strip
        raise PolicyError, "soulseek: query is empty or exceeds #{MAX_QUERY_BYTES} bytes" if text.empty? || text.bytesize > MAX_QUERY_BYTES
        raise PolicyError, "soulseek: query contains control characters" if text.match?(/[[:cntrl:]]/)
        text
      end

      def clean_search_id(value)
        id = value.to_s.strip
        raise PolicyError, "soulseek: search_id must be a UUID returned by search" unless id.match?(SEARCH_ID)
        id
      end

      def clean_username(value)
        name = value.to_s.strip
        raise PolicyError, "soulseek: invalid peer username" if name.empty? || name.bytesize > 500 || name.match?(/[[:cntrl:]]/)
        name
      end

      def clean_remote_filename(value)
        name = value.to_s.strip
        segments = name.tr("\\", "/").split("/")
        invalid = name.empty? || name.bytesize > 2_000 || name.match?(/[[:cntrl:]]/) ||
                  name.start_with?("/", "\\") || name.match?(/\A[A-Za-z]:/) ||
                  segments.any? { |part| part.empty? || part == "." || part == ".." }
        raise PolicyError, "soulseek: invalid remote filename" if invalid
        name
      end

      def audio_file?(filename)
        AUDIO_EXTENSIONS.include?(File.extname(filename.to_s).downcase)
      end

      def scan_library(path)
        value = path.to_s.strip
        raise PolicyError, "soulseek: give an explicit local music-library path" if value.empty?
        root = File.realpath(File.expand_path(value))
        raise PolicyError, "soulseek: refusing to scan the filesystem root" if root == File::SEPARATOR
        raise PolicyError, "soulseek: library path is not a directory" unless File.directory?(root)

        files = []
        extensions = Hash.new(0)
        bytes = 0
        truncated = false
        catch(:scan_limit) do
          Find.find(root) do |entry|
            stat = begin
              File.lstat(entry)
            rescue Errno::EACCES, Errno::ENOENT
              next
            end
            next unless stat.file? && audio_file?(entry)
            if files.length >= MAX_LIBRARY_FILES
              truncated = true
              throw :scan_limit
            end

            relative = entry.delete_prefix("#{root}#{File::SEPARATOR}")
            extension = File.extname(entry).downcase
            extensions[extension] += 1
            bytes += stat.size
            files << { relative_path: relative, size: stat.size, absolute_path: entry, extension: extension }
          end
        end
        {
          path: root, tracks: files.length, bytes:,
          extensions: extensions.sort.to_h, files:, truncated:
        }
      rescue Errno::ENOENT, Errno::ENOTDIR
        raise PolicyError, "soulseek: library path does not exist or is not accessible"
      end

      def normalize_title(value)
        value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
      end

      def query_matches_library?(query, candidates)
        words = normalize_title(query).split
        return false if words.empty?
        threshold = [(words.length * 0.6).ceil, 1].max
        candidates.any? do |candidate|
          words.count { |word| candidate.match?(/\b#{Regexp.escape(word)}\b/) } >= threshold
        end
      end

      def endpoint_uri
        uri = URI.parse(ENV.fetch("MASTER_SLSKD_URL", "http://127.0.0.1:5030").to_s.strip)
        invalid = !%w[http https].include?(uri.scheme) || uri.host.to_s.empty? ||
                  !uri.userinfo.nil? || !uri.query.nil? || !uri.fragment.nil? ||
                  uri.path.to_s.split("/").include?("..")
        raise PolicyError, "soulseek: invalid MASTER_SLSKD_URL" if invalid
        return uri if uri.scheme == "http" && loopback_host?(uri.hostname)

        unless uri.scheme == "https" && uri.port == 443 && Master::Io::SsrfGuard.pinned_address(uri)
          raise PolicyError, "soulseek: endpoint must be loopback HTTP or public HTTPS on port 443"
        end
        uri
      rescue URI::InvalidURIError
        raise PolicyError, "soulseek: invalid MASTER_SLSKD_URL"
      end

      def loopback_host?(host)
        return true if host.to_s.casecmp?("localhost")
        IPAddr.new(host.to_s).loopback?
      rescue IPAddr::InvalidAddressError
        false
      end

      def endpoint_label
        uri = endpoint_uri
        "#{uri.scheme}://#{uri.host}:#{uri.port}"
      rescue PolicyError
        "invalid"
      end

      def api_key
        value = ENV["MASTER_SLSKD_API_KEY"].to_s.strip
        value.empty? ? nil : value
      end

      def api_request(method, path, payload = nil)
        raise PolicyError, "soulseek: set MASTER_SLSKD_API_KEY in the process environment" unless api_key
        uri = api_uri(path)
        request = case method.to_s.downcase
                  when "get" then Net::HTTP::Get.new(uri.request_uri)
                  when "post" then Net::HTTP::Post.new(uri.request_uri)
                  else raise PolicyError, "soulseek: unsupported HTTP method"
                  end
        request["X-API-Key"] = api_key
        request["Accept"] = "application/json"
        if payload
          request["Content-Type"] = "application/json"
          request.body = JSON.generate(payload)
        end

        response, body = if local_http_endpoint?(endpoint_uri)
                           local_request(uri, request)
                         else
                           incoming = Master::Io::SsrfGuard.request(uri, request, max_bytes: MAX_RESPONSE_BYTES, timeout: REQUEST_TIMEOUT)
                           [incoming, incoming.body.to_s]
                         end
        code = response.code.to_i
        raise Error, "slskd API returned HTTP #{code}" unless code.between?(200, 299)
        return {} if body.empty?
        JSON.parse(body)
      rescue JSON::ParserError
        raise Error, "slskd returned malformed JSON"
      end

      def api_uri(path)
        base = endpoint_uri.dup
        prefix = base.path.to_s.sub(%r{/+\z}, "")
        suffix = path.to_s.sub(%r{\A/+}, "")
        raise PolicyError, "soulseek: invalid API path" if suffix.split("/").include?("..") || suffix.include?("%")
        base.path = "#{prefix}/api/v0/#{suffix}".gsub(%r{/+}, "/")
        base.query = nil
        base.fragment = nil
        base
      end

      def local_http_endpoint?(uri)
        uri.scheme == "http" && loopback_host?(uri.hostname)
      end

      def local_request(uri, request)
        http = Net::HTTP.new(uri.hostname, uri.port, nil)
        http.open_timeout = 3
        http.read_timeout = 8
        http.write_timeout = 5
        response = nil
        body = +""
        http.start do |client|
          client.request(request) do |incoming|
            response = incoming
            declared = incoming["content-length"].to_s
            raise Error, "slskd response exceeds #{MAX_RESPONSE_BYTES} bytes" if declared.match?(/\A\d+\z/) && declared.to_i > MAX_RESPONSE_BYTES
            incoming.read_body do |chunk|
              raise Error, "slskd response exceeds #{MAX_RESPONSE_BYTES} bytes" if body.bytesize + chunk.bytesize > MAX_RESPONSE_BYTES
              body << chunk
            end
          end
        end
        raise Error, "slskd returned no response" unless response
        [response, body]
      ensure
        begin
          http.finish if http&.started?
        rescue IOError, SystemCallError
          nil
        end
      end
    end
  end
end
