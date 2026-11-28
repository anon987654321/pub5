#!/usr/bin/env ruby
# frozen_string_literal: true

# mov 8.8 — multi-source torrent picker (output styled after OpenBSD dmesg)
#
#   ruby mov.rb                      taste discovery: festival winners, followed directors,
#                                    prestige list + wishlist, ranked against ~/.config/mov/taste.md
#   ruby mov.rb --source seeded      Apibay top-100 only
#   ruby mov.rb --source all         taste + seeded
#   ruby mov.rb "title"              explicit title
#   ruby mov.rb --recommend --limit 20 --include-bw
#   ruby mov.rb --stream-days 90     prioritize recent subscription catalog arrivals
# Keyless streaming calendar: GoodWatch NO/US, last 14 days on first run;
# retain dated arrivals for 90 days. Catalog arrival is not a global premiere.
#   ruby mov.rb --dry-run
#   ruby mov.rb --status / --check / --list / --prune [--yes] / --check-trackers
#   ruby mov.rb --stall-timeout SEC
#   ruby mov.rb --jobs N             download N titles at once (default 2)
#   ruby mov.rb --dead-after SEC     drop a stream with no data after SEC (default 600)
#
# Progress is a single line per update:
#   aria0: <Title> 42% 312/740MB 1.2MB/s 18 peers
#
# Ctrl-C marks the least-progressing active title as seen and removes its staging.
# Ctrl-\ quits. Ctrl-C between downloads is ignored during a run. Movies: 2022+.
# Excludes horror, gore, children's/family films, LGBTQ-focused stories,
# documentaries and biographies.
# Known Tomatometer scores below 75% are excluded; --min-rating 0 disables the floor.
# Scores come from Wikidata; --require-rating rejects unrated titles.
# IMDb IDs identify films but IMDb ratings are never used.
# Content screening is based on available metadata, not the video itself.
#
# Optional env:
#   MOV_DEST=~/Downloads
#
# REQUIRES: Ruby 3.0+; aria2c only for downloads.

$stdout.sync = true

require "json"
require "cgi"
require "uri"
require "net/http"
require "fileutils"
require "securerandom"
require "socket"
require "date"
require "time"
require "optparse"
require "open3"
require "digest"
require "monitor"
require "set"

ROOT       = File.expand_path(ENV["MOV_DEST"] || "~/Downloads")
CFG_DIR    = File.join(Dir.home, ".config", "mov")
STATE_PATH = File.join(CFG_DIR, "state.json")
SKIP_PATH  = File.join(CFG_DIR, "skip")
CACHE_DIR  = File.join(CFG_DIR, "cache")
STAGING    = File.join(ROOT, ".mov", "staging")
ARIA2_LOGS = File.join(CFG_DIR, "aria2")

CINEMETA  = "https://v3-cinemeta.strem.io"
TORRENTIO = "https://torrentio.strem.fun"
APIBAY    = "https://apibay.org"
GOODWATCH = "https://goodwatch.app"
# GoodWatch serves a cookie-gate shell to cookie-less clients; this cookie
# unlocks the server-rendered calendar. Without it every region parses empty.
GOODWATCH_COOKIE = "gw_browser=1"

MOV_VERSION = "8.8"
UA = "Mozilla/5.0 (compatible; mov/#{MOV_VERSION})"

SOURCES        = %w[taste seeded all].freeze
DEFAULT_SOURCE = "taste"

MIN_FREE_GB        = 5.0
MAX_RES            = 1080
MAX_EPISODES       = 20
TRACKER_TTL        = 7 * 86_400
STAGING_TTL        = 2 * 86_400
ARIA2_LOG_TTL      = 7 * 86_400
MAX_BODY           = 20 * 1024 * 1024
DEFAULT_STALL      = 1200
DEFAULT_DEAD       = 600
DEFAULT_JOBS       = 2
PICK_ATTEMPTS      = 3
DEAD_PICK_ATTEMPTS = 5
RPC_MISS_LIMIT     = 3
SEEDED_MIN_SEEDERS = 10
TASTE_WANT         = 10
STREAM_DAYS        = 90
MIN_MOVIE_YEAR     = 2022
MIN_RT_RATING      = 75
RT_TTL             = 7 * 86_400
RT_LOCK            = Mutex.new
DISCOVER_YEARS     = [Time.now.year - MIN_MOVIE_YEAR, 1].max
DISCOVER_PROBE     = 150
META_TTL           = 30 * 86_400
SEARCH_TTL         = 86_400
FAILED_TTL         = 86_400
DISCOVERY_BATCH    = 12

KEEP_CATS = %w[205 207 208].freeze

# 480/720p beat 1080p unless 1080p is dramatically better in every other way.
# A logarithmic bonus rewards availability without overwhelming resolution preference.
RES_SCORE  = { 480 => 50, 720 => 58, 1080 => 10 }.freeze
MIN_VIDEO_BYTES = 1024 * 1024
VIDEO_EXTS = %w[.mp4 .mkv .avi .m4v .webm].freeze
SUB_EXTS   = %w[.srt .ass .vtt].freeze

TRACKERS = %w[
  udp://tracker.opentrackr.org:1337/announce
  udp://open.stealth.si:80/announce
  udp://tracker.torrent.eu.org:451/announce
  udp://open.demonii.com:1337/announce
  udp://open.tracker.cl:1337/announce
  udp://exodus.desync.com:6969/announce
  udp://tracker.qu.ax:6969/announce
  udp://tracker.corpscorp.online:80/announce
  udp://tracker.ducks.party:1984/announce
  udp://tracker.bittor.pw:1337/announce
  udp://tracker-udp.gbitt.info:80/announce
  udp://tracker.nyaa.vc:6969/announce
  udp://tracker.tryhackx.org:6969/announce
  udp://tracker.gmi.gd:6969/announce
  udp://retracker01-msk-virt.corbina.net:80/announce
  udp://explodie.org:6969/announce
  udp://tracker2.dler.org:80/announce
  udp://tracker.dler.org:6969/announce
  udp://tracker.dler.com:6969/announce
  udp://tracker.wildkat.net:6969/announce
  udp://evan.im:6969/announce
  udp://tr4ck3r.duckdns.org:6969/announce
  udp://ns575949.ip-51-222-82.net:6969/announce
  udp://martin-gebhardt.eu:25/announce
  udp://open.ftorrent.com:443/announce
  udp://tracker.torrents.observer:80/announce
  udp://tracker.nyaa.net:6969/announce
  udp://tracker.cn.nyaa.net:6969/announce
  udp://tracker.aruku.ovh:8081/announce
  udp://kolankoalastree.newtrackon.co.nz:1337/announce
  udp://torrent.tracker.durukanbal.com:6969/announce
  udp://tracker.okade.pro:1337/announce
  udp://mail.segso.net:6969/announce
  udp://tracker.peerfect.org:6969/announce
  udp://tracker.opentrackr.com:6969/announce
  udp://tracker.playground.ru:6969/announce
  udp://ipv4announce.sktorrent.eu:6969/announce
  udp://opentracker.io:1337/announce
  udp://tracker.internetwarriors.net:1337/announce
  udp://tracker.leechers-paradise.org:6969/announce
  udp://tracker.cyberia.is:6969/announce
  https://tracker.tamersunion.org:443/announce
  https://tracker.foreverpirates.co:443/announce
  https://tracker.7471.top:443/announce
  https://tracker.pmman.tech:443/announce
  https://tracker.qingwapt.org:443/announce
  https://tracker.yume-hatsuyuki.moe:443/announce
  https://004430.xyz:443/announce
  https://1.tracker.eu.org:443/announce
  https://tracker.nekomi.cn:443/announce
  https://t.213891.xyz:443/announce
  http://tracker.files.fm:6969/announce
  http://tracker.opentrackr.org:1337/announce
  http://bt1.archive.org:6969/announce
  http://bt2.archive.org:6969/announce
  http://tracker.dler.com:6969/announce
  http://tracker.internetwarriors.net:1337/announce
  http://tracker.renfei.net:8080/announce
  http://tracker.mywaifu.best:6969/announce
  http://tracker.waaa.moe:6969/announce
  http://tracker.dhitechnical.com:6969/announce
].freeze

HTTP_TRACKERS = %w[
  http://tracker.opentrackr.org:1337/announce
  http://tracker.renfei.net:8080/announce
  http://tracker.mywaifu.best:6969/announce
  https://tracker.pmman.tech:443/announce
].freeze

Target = Struct.new(:title, :year, :media_type, :imdb_id, :est_mb, keyword_init: true) do
  def movie? = media_type == :movie
  def tv?    = media_type == :tv
end

# Concurrency model: --jobs N worker threads, each running one title at a time.
# LOCK guards state, stats, the in-flight registry and disk reservations.
# Signal handlers publish requests; workers assign them under LOCK.
LOCK = Monitor.new

$exit_now     = false
$stop_new     = false
$skip_requests = 0
$skip_handled  = 0
$pool_running  = false
$dead_after   = DEFAULT_DEAD
$active       = {}
$inflight     = Set.new
$reserved_gb  = 0.0

Signal.trap("INT") do
  if !$active.empty?
    $skip_requests += 1
  elsif !$pool_running
    $exit_now = true
  end
end
Signal.trap("QUIT") { $exit_now = true }
Signal.trap("TERM") { $exit_now = true }

def skip_requested? = Thread.current[:skip] == true
def reset_skip      = (Thread.current[:skip] = false)

def discovery_since
  [MIN_MOVIE_YEAR, Time.now.year - ($discover_years || DISCOVER_YEARS)].max
end

def movie_year_allowed?(year, since: MIN_MOVIE_YEAR)
  year.to_i.between?(since, Time.now.year)
end

# Lines follow OpenBSD dmesg: "dev0 at parent0: description", "dev0: event".
def say(msg)
  unit = Thread.current[:unit]
  msg  = msg.sub(/\A(aria|indexer|disk)0([: ])/) { "#{$1}#{unit}#{$2}" } if unit
  LOCK.synchronize { $stdout.write("#{msg}\n") }
end

def human_gb(bytes) = format("%.1fGB", bytes / 1024.0**3)

def bump(h, key) = LOCK.synchronize { h[key] += 1 }

# Assign each interrupt to a different active download, never a future title.
def claim_skip!
  LOCK.synchronize do
    while $skip_handled < $skip_requests
      $skip_handled += 1
      stuck = $active.reject { |worker, _| worker[:skip] }
                     .min_by { |_, status| status[:last_change] }&.first
      stuck[:skip] = true if stuck
    end
  end
end

def dir_size(path)
  return 0 unless File.directory?(path)
  Dir.glob(File.join(path, "**", "*")).sum do |f|
    st = begin
      File.lstat(f)
    rescue StandardError
      nil
    end
    next 0 unless st&.file?
    [st.blocks.to_i * 512, st.size].min
  end
end

class State
  def initialize(path)
    @path = path
    @lock = Monitor.new
    @data = read
    repair_incomplete
  end

  def read
    return fresh_data unless File.exist?(@path)
    raw  = File.read(@path)
    data = begin
      JSON.parse(raw)
    rescue StandardError
      nil
    end
    unless data.is_a?(Hash)
      backup = "#{@path}.bak.#{Time.now.to_i}"
      begin
        FileUtils.cp(@path, backup)
      rescue StandardError
        nil
      end
      say("mov0: corrupt state at #{@path}, backed up to #{backup}, starting fresh")
      return fresh_data
    end
    data["version"]    ||= 1
    data["downloaded"] ||= {}
    data
  end

  # Older versions could mistake magnet metadata for completed video.
  # Preserve files and records, but do not count these as watched or complete.
  def repair_incomplete
    changed = 0
    @data["downloaded"].each_value do |v|
      next unless v.is_a?(Hash) && v["status"] == "completed"
      path = v["path"].to_s
      small = v.key?("size") && v["size"].to_i < MIN_VIDEO_BYTES
      small ||= File.file?(path) && File.size(path) < MIN_VIDEO_BYTES
      next unless small
      v["status"] = "incomplete"
      v["reason"] = "legacy completion without a full video"
      changed += 1
    end
    return if changed.zero?
    save
    say("db0: #{changed} incomplete legacy records made retryable; files preserved")
  end

  def fresh_data = { "version" => 8, "downloaded" => {} }

  def save
    @lock.synchronize do
      FileUtils.mkdir_p(File.dirname(@path))
      tmp = "#{@path}.tmp.#{Process.pid}.#{rand(2**32)}"
      File.open(tmp, "w") do |f|
        f.write(JSON.pretty_generate(@data))
        f.flush
        f.fsync
      end
      File.rename(tmp, @path)
    end
  end

  def tracked?(key)
    @lock.synchronize do
      v = @data["downloaded"][key] or return false
      ttl = case v["status"]
            when "unavailable" then 7 * 86_400
            when "failed" then FAILED_TTL
            when "incomplete" then return false
            else return true
            end
      Time.now.utc - Time.parse(v.fetch("at")) < ttl
    end
  rescue ArgumentError, KeyError, TypeError
    false
  end

  def mark(key, status, info)
    @lock.synchronize do
      @data["downloaded"][key] = info.merge("status" => status, "at" => Time.now.utc.iso8601)
      save
    end
  end

  def mark_unavailable(key, info) = mark(key, "unavailable", info)
  def mark_completed(key, info)   = mark(key, "completed", info)
  def mark_skipped(key, info)     = mark(key, "skipped", info)
  def mark_failed(key, info)      = mark(key, "failed", info)

  def status(key)
    @lock.synchronize { @data["downloaded"].dig(key, "status") }
  end

  def delete(key)
    @lock.synchronize do
      return unless @data["downloaded"].key?(key)
      @data["downloaded"].delete(key)
      save
    end
  end

  def clear_status(*statuses)
    @lock.synchronize do
      n = 0
      @data["downloaded"].delete_if { |_, v| statuses.include?(v["status"]) ? (n += 1) : false }
      save
      n
    end
  end

  def counts
    @lock.synchronize do
      dl = @data["downloaded"]
      {
        total:     dl.size,
        completed: dl.values.count { |v| v["status"] == "completed" },
        skipped:   dl.values.count { |v| %w[skipped interrupted].include?(v["status"]) },
        failed:    dl.values.count { |v| v["status"] == "failed" },
        bytes:     dl.values.select { |v| v["status"] == "completed" }.sum { |v| v["size"].to_i },
      }
    end
  end

  def all
    @lock.synchronize { @data["downloaded"].dup }
  end
end

class Cache
  def initialize(dir)
    @dir = dir
    FileUtils.mkdir_p(@dir)
  end

  def get(name, ttl)
    path = File.join(@dir, "#{name}.json")
    return nil unless File.exist?(path)
    data = begin
      JSON.parse(File.read(path))
    rescue StandardError
      nil
    end
    return nil unless data.is_a?(Hash)
    if data["_at"].is_a?(String)
      return nil if Time.now.utc - Time.parse(data["_at"]) > ttl
    end
    data
  rescue StandardError
    nil
  end

  def put(name, data)
    path = File.join(@dir, "#{name}.json")
    payload = data.merge("_at" => (data["_at"] || Time.now.utc.iso8601))
    tmp = "#{path}.#{Process.pid}.#{SecureRandom.hex(6)}.tmp"
    File.write(tmp, JSON.generate(payload))
    File.rename(tmp, path)
  rescue StandardError
    nil
  ensure
    FileUtils.rm_f(tmp) if tmp
  end
end

# HTTP chunks arrive as bytes; decode once after the complete response.
def utf8_text(value)
  text = value.to_s
  if text.encoding == Encoding::BINARY
    text = text.dup.force_encoding(Encoding::UTF_8)
  end
  text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace).scrub
end

def http_get(url, headers: {}, retries: 2, follow: 3)
  uri = URI(url)
  req = Net::HTTP::Get.new(uri)
  req["User-Agent"] = UA
  headers.each { |k, v| req[k] = v }

  (1..retries).each do |attempt|
    begin
      body = +"".b
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                            open_timeout: 5, read_timeout: 12, max_retries: 0) do |h|
        h.request(req) do |response|
          if response.is_a?(Net::HTTPSuccess)
            response.read_body do |chunk|
              return nil if body.bytesize + chunk.bytesize > MAX_BODY
              body << chunk
            end
          end
        end
      end
      return utf8_text(body) if res.is_a?(Net::HTTPSuccess)
      code = res.code.to_i
      if [301, 302, 307, 308].include?(code) && follow.positive?
        loc = res["Location"].to_s
        return nil if loc.empty?
        return http_get(URI.join(url, loc).to_s, headers: headers, retries: retries, follow: follow - 1)
      end
      return nil if code >= 400 && code < 500 && ![408, 429].include?(code)
      sleep(2**(attempt - 1)) if attempt < retries
    rescue StandardError
      sleep(2**(attempt - 1)) if attempt < retries
    end
  end
  nil
end

def http_json(url, headers: {})
  body = http_get(url, headers: headers)
  return nil unless body
  begin
    JSON.parse(body)
  rescue StandardError
    nil
  end
end

def preflight!(download: true)
  errors = []

  rv = RUBY_VERSION.split(".").map(&:to_i)
  rv += [0, 0, 0]
  errors << "ruby #{RUBY_VERSION} too old (need 3.0+)" unless (rv[0, 3] <=> [3, 0, 0]) >= 0

  if download && !Open3.capture2e("which", "aria2c")[1].success?
    errors << "aria2c missing (install aria2 using your package manager)"
  end

  begin
    FileUtils.mkdir_p([ROOT, CFG_DIR, CACHE_DIR, STAGING, ARIA2_LOGS])
  rescue StandardError => e
    errors << "cannot create dirs: #{e.message}"
    errors.each { |err| say("mov0: #{err}") }
    exit 1
  end

  [ROOT, STAGING, ARIA2_LOGS].each do |d|
    probe = File.join(d, ".mov-write-#{Process.pid}-#{rand(2**32)}")
    begin
      File.write(probe, "")
      File.delete(probe)
    rescue StandardError => e
      errors << "cannot write to #{d} (#{e.message})"
    end
  end

  if errors.any?
    errors.each { |e| say("mov0: #{e}") }
    exit 1
  end
end

def free_gb
  out, status = Open3.capture2e("df", "-k", ROOT)
  return 0.0 unless status.success?
  out.lines.drop(1).last.to_s.split[3].to_i / 1024.0 / 1024.0
rescue StandardError
  0.0
end

def release_label(name, size_bytes, seeds)
  mb = (size_bytes.to_i / 1024.0 / 1024).round
  "#{name} 💾 #{mb} MB 👤 #{seeds}"
end

def size_mib(title)
  m = title.to_s.match(/💾\s*([\d.]+)\s*(GB|GiB|MB|MiB|TB|TiB)/i)
  return 1200 unless m
  case m[2].downcase[0]
  when "g" then (m[1].to_f * 1024).round
  when "t" then (m[1].to_f * 1024 * 1024).round
  else          m[1].to_f.round
  end
end

def resolution(title)
  s = title.to_s.downcase
  return 2160 if s.match?(/\b(2160p|4k|uhd)\b/)
  return 1080 if s.match?(/\b(1080p|fhd)\b/)
  return 720  if s.match?(/\b(720p|hd)\b/)
  return 480  if s.match?(/\b(480p|sd|576p)\b/)
  nil
end

def not_dubbed?(title)
  s = title.to_s
  return false if s.match?(/\b(dubbed|truefrench|vf|vff)\b/i)
  true
end

def normalize_hash(value)
  text = value.to_s
  return text.downcase if text.match?(/\A[a-fA-F0-9]{40}\z/)
  return nil unless text.match?(/\A[A-Z2-7]{32}\z/i)
  alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
  bits = text.upcase.chars.map { |c| alphabet.index(c).to_s(2).rjust(5, "0") }.join
  [bits].pack("B*").unpack1("H*")
end

def infohash(stream)
  direct = normalize_hash(stream["infoHash"])
  return direct if direct
  uri = URI.parse(stream["url"].to_s)
  return nil unless uri.scheme == "magnet"
  query = uri.query || uri.opaque.to_s.sub(/\A\?/, "")
  URI.decode_www_form(query).each do |key, value|
    next unless key == "xt" && value.match?(/\Aurn:btih:/i)
    hash = normalize_hash(value.sub(/\Aurn:btih:/i, ""))
    return hash if hash
  end
  nil
rescue URI::InvalidURIError, ArgumentError
  nil
end

def score_stream(stream)
  t = stream["title"].to_s
  r = stream["_res"] || resolution(t)
  return nil unless RES_SCORE.key?(r) && r <= MAX_RES
  return nil unless not_dubbed?(t)
  return nil unless infohash(stream)

  seeds = stream["seeds"].to_i
  seeds = t[/👤\s*(\d+)/, 1].to_i if seeds.zero?
  seeds = [seeds, 0].max

  score  = RES_SCORE.fetch(r, 0)
  score += t =~ /\.mp4\b|\bmp4\b/i ? 10 : 0
  score += t =~ /x\.?264|h\.?264|avc/i ? 8 : 0
  score += [5 * Math.log2(seeds + 1), 35].min
  score -= 25 if seeds < 3
  score -= 20 if size_mib(t) > 3000
  score -= Math.log10([size_mib(t), 1].max) * 3

  stream.merge("_score" => score, "_res" => r, "_seeds" => seeds)
end

def best_streams(streams, limit: PICK_ATTEMPTS)
  streams.filter_map { |s| score_stream(s) }.sort_by { |s| -s["_score"] }.first(limit)
end

# Indexers list one release from several swarms; identical size, resolution
# and release name mean a retry would repeat the same dead swarm.
def release_identity(stream)
  [size_mib(stream["title"]), stream["_res"] || resolution(stream["title"]),
   title_identity(stream["title"].to_s.sub(/\s*💾.*\z/, ""))]
end

def clean_title(t)
  s = utf8_text(t).unicode_normalize(:nfd).gsub(/[^\x00-\x7F]/, "")
       .downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "").squeeze("_")
  return "t_#{Digest::SHA1.hexdigest(t.to_s)[0, 8]}" if s.empty?
  s
end

def dest_name(title, year: nil, season: nil, episode: nil)
  c = clean_title(title)
  if season && episode
    "#{c}_s#{format('%02d', season)}e#{format('%02d', episode)}"
  elsif year
    "#{c}_#{year}"
  else
    c
  end
end

def tracker_list(cache)
  cached = cache.get("trackers", TRACKER_TTL)
  udp = if cached && cached["list"].is_a?(Array) && cached["list"].any?
          cached["list"]
        else
          TRACKERS.select(&:ascii_only?).select { |u| (URI.parse(u) rescue nil) }
        end
  HTTP_TRACKERS | udp
rescue StandardError
  HTTP_TRACKERS | TRACKERS
end

def stream_trackers(stream)
  Array(stream["sources"]).filter_map do |s|
    next unless s.is_a?(String) && s.start_with?("tracker:")
    t = s.sub(/\Atracker:/, "")
    next unless t.start_with?("udp://", "http://", "https://")
    begin
      URI.parse(t)
      t
    rescue StandardError
      nil
    end
  end
end

# aria2c JSON-RPC client. One aria2 process per download keeps the model simple
# and lets us read completedLength/totalLength for a real percentage.
class Aria2
  class Error < StandardError; end

  attr_reader :port, :rpc_error

  def initialize(log_path)
    @log = log_path
    last_error = nil
    3.times do
      @exit_reason = nil
      @rpc_error = nil
      @port   = self.class.free_port
      @secret = SecureRandom.hex(8)
      @pid    = Process.spawn(*command, out: File::NULL, err: File::NULL, pgroup: true)
      begin
        wait_ready
        return
      rescue Error => e
        last_error = e
        stop
      end
    end
    raise(last_error || Error.new("aria2 failed to start"))
  end

  def self.free_port
    server = TCPServer.new("127.0.0.1", 0)
    port   = server.addr[1]
    server.close
    port
  end

  def command
    [
      "aria2c",
      "--enable-rpc=true",
      "--rpc-listen-all=false",
      "--rpc-allow-origin-all=false",
      "--rpc-listen-port=#{@port}",
      "--rpc-secret=#{@secret}",
      "--rpc-max-request-size=16M",
      "--seed-time=0",
      "--file-allocation=none",
      "--enable-dht=true",
      "--enable-peer-exchange=true",
      "--bt-enable-lpd=true",
      "--bt-max-peers=80",
      "--max-tries=0",
      "--console-log-level=error",
      "--summary-interval=0",
      "--log=#{@log}",
      "--log-level=notice",
      "--split=4",
      "--max-connection-per-server=4",
    ]
  end

  def wait_ready(timeout: 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return if rpc("aria2.getVersion")
      reason = exit_reason
      raise Error, reason if reason
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        raise Error, "aria2 rpc not ready"
      end
      sleep 0.2
    end
  end

  def rpc(method, params = [])
    body = JSON.generate(
      jsonrpc: "2.0",
      id: SecureRandom.hex(4),
      method: method,
      params: ["token:#{@secret}", *params],
    )
    uri = URI("http://127.0.0.1:#{@port}/jsonrpc")
    http = Net::HTTP.new(uri.host, uri.port, nil)
    http.open_timeout = 2
    http.read_timeout = 5
    res = http.start do |h|
      h.post(uri.path, body, "Content-Type" => "application/json")
    end
    unless res.is_a?(Net::HTTPSuccess)
      @rpc_error = "HTTP #{res.code}"
      return nil
    end
    data = JSON.parse(res.body)
    @rpc_error = data.dig("error", "message")
    data["result"]
  rescue StandardError => e
    @rpc_error = "#{e.class}: #{e.message}"
    nil
  end

  def exit_reason
    return @exit_reason unless @pid
    pair = Process.waitpid2(@pid, Process::WNOHANG)
    return nil unless pair
    @pid = nil
    status = pair.last
    @exit_reason = status.signaled? ? "aria2 terminated by signal #{status.termsig}" : "aria2 exited (status #{status.exitstatus})"
  rescue Errno::ECHILD
    @pid = nil
    @exit_reason = "aria2 child no longer exists"
  end

  def add(uri, dir:, trackers:, select: nil)
    opts = {
      "dir"             => dir,
      "seed-time"       => "0",
      "file-allocation" => "none",
      "bt-tracker"      => trackers.join(","),
    }
    opts["select-file"] = select.to_s if select
    rpc("aria2.addUri", [[uri], opts])
  end

  def status(gid)
    rpc("aria2.tellStatus",
        [gid, %w[gid status totalLength completedLength downloadSpeed
                 connections numSeeders seeder errorCode errorMessage followedBy]])
  end

  def completed_files(gid, staging)
    files = rpc("aria2.getFiles", [gid])
    return [] unless files.is_a?(Array)
    root = File.realpath(staging) + File::SEPARATOR
    selected = files.select { |f| f["selected"].to_s == "true" }
    paths = selected.map do |f|
      path = f["path"].to_s
      length = f["length"].to_i
      return [] unless length.positive? && f["completedLength"].to_i == length
      return [] unless File.file?(path) && !File.symlink?(path)
      real = File.realpath(path)
      return [] unless real.start_with?(root) && File.size(real) == length
      real
    end
    return [] unless paths.any? { |path| VIDEO_EXTS.include?(File.extname(path).downcase) && File.size(path) >= MIN_VIDEO_BYTES }
    paths
  rescue SystemCallError
    []
  end

  def remove(gid)
    rpc("aria2.forceRemove", [gid])
  rescue StandardError
    nil
  end

  def stop
    pid = @pid or return
    @pid = nil
    rpc("aria2.forceShutdown")
    10.times do
      return if Process.waitpid(pid, Process::WNOHANG)
      sleep 0.1
    end
    Process.kill("KILL", -pid)
    Process.waitpid(pid)
  rescue Errno::ECHILD, Errno::ESRCH
    nil
  end
end

def human_wait(seconds)
  s = seconds.to_i
  s >= 120 ? "#{(s / 60.0).round}min" : "#{s}s"
end

def format_progress(title, done, total, speed, peers)
  pct = total.positive? ? (done * 100 / total) : 0
  dmb = (done / 1024.0**2).round
  tmb = (total / 1024.0**2).round
  return "aria0: #{title[0, 40]} 100% #{tmb}MB" if pct >= 100
  smb = (speed / 1024.0**2).round(1)
  "aria0: #{title[0, 40]} #{pct}% #{dmb}/#{tmb}MB #{smb}MB/s #{peers} peers"
end

def aria2_download(stream, hash, staging, trackers, title, stall:)
  log = File.join(ARIA2_LOGS, "#{hash[0, 8]}-#{Time.now.to_i}.log")
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  LOCK.synchronize do
    claim_skip!
    $active[Thread.current] = { label: title[0, 40], last_change: started }
  end
  client = Aria2.new(log)

  uri = stream["_uri"] || stream["url"] || "magnet:?xt=urn:btih:#{hash}"
  select = (stream["fileIdx"] && !stream["_uri"] && !stream["url"]) ? stream["fileIdx"].to_i + 1 : nil
  max_bytes = (stream["_direct"] || stream["_uri"] || stream["url"]) ? nil : (size_mib(stream["title"]) * 1024**2 * 1.5).to_i

  claim_skip!
  return [:interrupted, nil, log] if skip_requested? || $exit_now
  gid = client.add(uri, dir: staging, trackers: trackers, select: select)
  return [:failed, "aria2 rejected the download", log] unless gid

  started     = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  last_bytes  = 0
  last_change = started
  last_print  = started
  print_bytes = 0
  meta_print  = started + 30
  meta_gap    = 90
  last_pct    = -10
  rpc_misses  = 0

  loop do
    claim_skip!
    if skip_requested? || $exit_now
      client.remove(gid)
      return [:interrupted, nil, log]
    end
    st = client.status(gid)
    claim_skip!
    if skip_requested? || $exit_now
      client.remove(gid)
      return [:interrupted, nil, log]
    end
    unless st
      reason = client.exit_reason
      return [:failed, reason, log] if reason
      rpc_misses += 1
      if rpc_misses >= RPC_MISS_LIMIT
        return [:failed, "RPC unavailable after #{rpc_misses} checks: #{client.rpc_error || 'no status'}", log]
      end
      say("aria0: #{title[0, 40]} RPC interrupted; checking again") if rpc_misses == 1
      sleep 1
      next
    end
    if rpc_misses.positive?
      say("aria0: #{title[0, 40]} RPC recovered")
      rpc_misses = 0
    end

    done   = st["completedLength"].to_i
    total  = st["totalLength"].to_i
    speed  = st["downloadSpeed"].to_i
    status = st["status"].to_s

    if done != last_bytes
      last_bytes  = done
      last_change = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      LOCK.synchronize do
        $active[Thread.current][:last_change] = last_change if $active[Thread.current]
      end
    end
    if status == "complete"
      next_gid = Array(st["followedBy"]).first
      unless next_gid && next_gid != gid
        paths = client.completed_files(gid, staging)
        return [:failed, "completion did not contain a verified full video", log] if paths.empty?
        return [:ok, nil, log, paths]
      end
      say("aria0: #{title[0, 40]} metadata complete; starting content")
      gid = next_gid
      last_bytes = 0
      last_change = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      started = last_change
      last_pct = -10
      last_print = started
      print_bytes = 0
      meta_print = started + 30
      meta_gap = 90
      LOCK.synchronize { $active[Thread.current][:last_change] = started if $active[Thread.current] }
      next
    end
    if %w[error removed].include?(status)
      return [:failed, "aria2 #{st['errorCode']}: #{st['errorMessage']}", log]
    end

    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    if total >= MIN_VIDEO_BYTES
      pct = (done * 100 / total)
      if pct >= last_pct + 10 || (now - last_print) >= 30
        span = now - last_print
        rate = speed.positive? || span < 1 ? speed : (done - print_bytes) / span
        say(format_progress(title, done, total, rate, st["connections"].to_i))
        last_pct    = pct / 10 * 10
        last_print  = now
        print_bytes = done
      end
    elsif now >= meta_print
      left = [($dead_after - (now - started)).ceil, 0].max
      if left.positive?
        peers = st["connections"].to_i
        say("aria0: #{title[0, 40]} waiting for metadata, #{peers} peers, drop in #{human_wait(left)}")
      end
      meta_gap   = [meta_gap * 2, 300].min
      meta_print = now + meta_gap
    end

    dead     = done < 1024 * 1024 && (now - started) > $dead_after
    stalled  = (now - last_change) > stall
    oversize = max_bytes && [done, total].max > max_bytes
    if skip_requested? || $exit_now || dead || stalled || oversize
      client.remove(gid)
      if skip_requested? || $exit_now
        return [:interrupted, nil, log]
      end
      reason = if oversize
                 "grew to #{(done / 1024.0**2).round}MB, over 1.5x the listed size (pack?)"
               elsif dead
                 "dead swarm, no data in #{($dead_after / 60.0).round}min"
               else
                 "stalled #{(stall / 60.0).round}min at #{(done / 1024.0**2).round}MB"
               end
      return [dead ? :dead : :failed, reason, log]
    end
    sleep 2
  end
rescue Aria2::Error => e
  [:failed, "aria2: #{e.message}", log]
ensure
  begin
    client&.stop
  ensure
    LOCK.synchronize do
      claim_skip!
      $active.delete(Thread.current)
    end
  end
end

def move_media(staging, dest_dir, title, year, res, season: nil, episode: nil, verified_paths: [])
  videos = []
  subs   = []
  verified_paths.each do |f|
    next unless File.file?(f) && !File.symlink?(f)
    next unless File.realpath(f).start_with?(File.realpath(staging) + File::SEPARATOR)
    ext = File.extname(f).downcase
    videos << f if VIDEO_EXTS.include?(ext) && File.size(f) >= MIN_VIDEO_BYTES
    subs   << f if SUB_EXTS.include?(ext) && File.size(f).positive?
  end
  return [] if videos.empty?

  FileUtils.mkdir_p(dest_dir)
  main = videos.max_by { |v| File.size(v) }
  ext  = File.extname(main).downcase
  base = dest_name(title, year: year, season: season, episode: episode)
  rtag = res ? "_#{res}p" : ""
  vdest = File.join(dest_dir, "#{base}#{rtag}#{ext}")
  vdest = File.join(dest_dir, "#{base}#{rtag}.#{SecureRandom.hex(3)}#{ext}") if File.exist?(vdest)
  FileUtils.mv(main, vdest)
  moved = [vdest]

  main_stem = File.basename(main, ext)
  subs.each_with_index do |sub, i|
    sext = File.extname(sub).downcase
    label = File.basename(sub, sext)
    label = label.sub(/\A#{Regexp.escape(main_stem)}/i, "")
    label = label.gsub(/\A[._-]+/, "")
    label = "sub#{i + 1}" if label.empty?
    sdest = File.join(dest_dir, "#{base}.#{label}#{sext}")
    sdest = File.join(dest_dir, "#{base}.#{label}.#{SecureRandom.hex(3)}#{sext}") if File.exist?(sdest)
    FileUtils.mv(sub, sdest)
    moved << sdest
  end
  moved
end

def download_attempt(stream, key, title, year, dest_dir, state, cache,
                     season: nil, episode: nil, stall: DEFAULT_STALL)
  return :skipped_by_user if skip_requested?
  return :interrupted if $exit_now

  hash = infohash(stream)
  return :failed unless hash

  needed_gb = (size_mib(stream["title"]) / 1024.0) * 1.2
  claim = LOCK.synchronize do
    if $inflight.include?(hash) || $inflight.include?(key)
      :busy
    elsif free_gb - $reserved_gb < needed_gb + MIN_FREE_GB
      :disk_full
    else
      $inflight << hash << key
      $reserved_gb += needed_gb
      :ok
    end
  end
  if claim == :busy
    say("mov0: #{title} already downloading in another worker")
    return :busy
  end
  if claim == :disk_full
    say("disk0: skip need #{needed_gb.round(1)}GB + #{MIN_FREE_GB}GB reserve; #{(free_gb - $reserved_gb).round(1)}GB unreserved")
    return :disk_full
  end

  begin
    run_download(stream, hash, key, title, year, dest_dir, state, cache,
                 season: season, episode: episode, stall: stall)
  ensure
    LOCK.synchronize do
      $inflight.delete(hash)
      $inflight.delete(key)
      $reserved_gb -= needed_gb
    end
  end
end

def run_download(stream, hash, key, title, year, dest_dir, state, cache,
                 season: nil, episode: nil, stall: DEFAULT_STALL)
  staging = File.join(STAGING, hash)
  FileUtils.mkdir_p(staging)
  desc = [title, year, stream["_res"] && "#{stream['_res']}p"].compact.join(", ")
  host = begin
    URI(stream["_uri"] || stream["url"]).host
  rescue StandardError
    nil
  end
  meta = host || "#{size_mib(stream['title'])}MB, #{stream['_seeds'].to_i} seeds"
  say("aria0: <#{desc}> #{meta}")

  trackers = tracker_list(cache) | stream_trackers(stream)
  result, reason, log, paths = aria2_download(stream, hash, staging, trackers, title, stall: stall)

  if skip_requested?
    state.mark_skipped(key, { "title" => title, "year" => year })
    bytes = dir_size(staging)
    FileUtils.remove_entry(staging) if File.exist?(staging)
    say("aria0: #{title} marked seen; staging removed (#{(bytes / 1024.0**2).round}MB)")
    return :skipped_by_user
  end

  if result == :ok
    moved = move_media(staging, dest_dir, title, year, stream["_res"],
                       season: season, episode: episode, verified_paths: paths)
    if moved.empty?
      say("aria0: completion rejected; no verified video moved, staging preserved")
      return :failed
    end
    FileUtils.rm_rf(staging)

    total = moved.sum { |p| File.size(p) rescue 0 }
    state.mark_completed(key, {
      "title" => title, "year" => year,
      "path"  => moved.first, "size" => total,
    })
    moved.each do |p|
      mb = (File.size(p) / (1024.0**2)).round rescue 0
      say("aria0: #{File.basename(p)} #{mb}MB")
    end
    return :ok
  end

  media_bytes = dir_size(staging)
  if $exit_now && !skip_requested?
    say("aria0: #{title} interrupted, staging kept for resume")
    return :interrupted
  end
  if media_bytes >= 1024 * 1024
    say("aria0: failed, staging kept (#{(media_bytes / 1024.0**2).round}MB) — #{reason}") if reason
  else
    FileUtils.rm_rf(staging)
    say("aria0: failed — #{reason}") if reason
  end
  say("aria0: log #{log}") if log && File.exist?(log)
  result == :dead ? :dead : :failed
end

def attempt_streams(streams, key, title, year, dest_dir, state, cache,
                    season: nil, episode: nil, stall: DEFAULT_STALL)
  picks = streams.all? { |s| s["_direct"] } ? streams : best_streams(streams, limit: DEAD_PICK_ATTEMPTS)
  return :no_streams if picks.empty?

  tried = Set.new
  attempts = 0
  dead = 0
  picks.each do |s|
    id = release_identity(s)
    next if tried.include?(id)
    tried << id
    r = download_attempt(s, key, title, year, dest_dir, state, cache,
                         season: season, episode: episode, stall: stall)
    return r if %i[ok disk_full skipped_by_user interrupted busy].include?(r)
    attempts += 1
    dead += 1 if r == :dead
    # A dead swarm says little about the other releases, so allow more tries.
    break if dead >= DEAD_PICK_ATTEMPTS
    break if r != :dead && attempts >= PICK_ATTEMPTS
  end
  :failed
end

def series_episodes(imdb_id)
  meta = cinemeta_meta("series", imdb_id)
  return [] unless meta && meta["videos"].is_a?(Array)
  today = Date.today
  aired = meta["videos"].select do |v|
    next false unless v["season"].to_i.positive?
    rel = v["released"]
    next false if rel.nil?
    begin
      Date.parse(rel) <= today
    rescue StandardError
      false
    end
  end
  return [] if aired.empty?
  latest = aired.map { |v| v["season"].to_i }.max
  aired.select { |v| v["season"].to_i == latest }
       .sort_by { |v| v["episode"].to_i }
       .first(MAX_EPISODES)
end

def skip_reason(st)
  case st
  when "completed"   then "already have"
  when "skipped"     then "skipped previously (--reset-skipped to retry)"
  when "interrupted" then "skipped previously (--reset-skipped to retry)"
  when "failed"      then "failed recently (retry in 24h or --reset-failed)"
  when "unavailable" then "unavailable recently (retry in 7 days)"
  else                    "already have"
  end
end

def skip_listed?(target)
  return false unless File.exist?(SKIP_PATH)
  File.readlines(SKIP_PATH, chomp: true).any? do |l|
    l = l.sub(/#.*/, "").strip
    next false if l.empty?
    l == target.imdb_id || l.casecmp?(target.title.to_s)
  end
rescue StandardError
  false
end

$torrentio_throttle = nil
$apibay_throttle    = nil

class Throttle
  def initialize(interval)
    @interval = interval
    @mutex    = Mutex.new
    @last     = Time.now - interval
  end

  def wait
    @mutex.synchronize do
      delay = @interval - (Time.now - @last)
      sleep(delay) if delay.positive?
      @last = Time.now
    end
  end
end

$torrentio_throttle = Throttle.new(1.5)
$apibay_throttle    = Throttle.new(1.0)

def torrentio_streams(type, id)
  key = [type.to_s, id]
  hit = LOCK.synchronize { ($stream_cache ||= {})[key] }
  return hit if hit
  $torrentio_throttle.wait
  data = http_json("#{TORRENTIO}/stream/#{type}/#{id}.json")
  return [] unless data.is_a?(Hash) && data["streams"].is_a?(Array)
  streams = data["streams"]
  LOCK.synchronize { $stream_cache[key] = streams }
  streams
end

def apibay_query_string(title, year: nil, season: nil, episode: nil)
  base = title.to_s.sub(/\AThe\s+/i, "").strip
  if season && episode
    "#{base} S#{format('%02d', season)}E#{format('%02d', episode)}"
  elsif year
    "#{base} #{year}"
  else
    base
  end
end

def apibay_streams(title, year: nil, season: nil, episode: nil)
  q = apibay_query_string(title, year: year, season: season, episode: episode)
  return [] if q.empty?

  $apibay_throttle.wait
  data = http_json("#{APIBAY}/q.php?q=#{CGI.escape(q)}&cat=200")
  return [] unless data.is_a?(Array)

  data.filter_map do |t|
    next unless t.is_a?(Hash)
    next if t["id"].to_s == "0"
    h = t["info_hash"].to_s.downcase
    next unless h.match?(/\A[a-f0-9]{40}\z/)
    {
      "title"    => release_label(t["name"], t["size"], t["seeders"]),
      "infoHash" => h,
      "seeds"    => t["seeders"].to_i,
      "_source"  => "apibay",
    }
  end
rescue StandardError
  []
end

def find_streams(kind, stream_id, title, year: nil, season: nil, episode: nil)
  from_torrentio = torrentio_streams(kind, stream_id)
  from_apibay    = apibay_streams(title, year: year, season: season, episode: episode)
  merged = (from_torrentio + from_apibay).uniq { |s| infohash(s) }

  sources = []
  sources << "torrentio #{from_torrentio.size}" if from_torrentio.any?
  sources << "apibay #{from_apibay.size}"       if from_apibay.any?
  if sources.any?
    ep = season ? " S#{format('%02d', season)}E#{format('%02d', episode)}" : ""
    say("indexer0: #{title}#{ep} — #{sources.join(', ')}, merged #{merged.size}")
  end
  merged
end

def apibay_top_recent
  [
    "#{APIBAY}/precompiled/data_top100_recent.json",
    "#{APIBAY}/precompiled/data_top100_48h.json",
  ].each do |url|
    data = http_json(url)
    return data if data.is_a?(Array) && data.any?
  end
  []
end

def seeded_candidates(state, _cache)
  raw = apibay_top_recent
  return [] if raw.empty?

  out = []
  raw.each do |t|
    next unless t.is_a?(Hash)
    cat = t["category"].to_s
    next unless KEEP_CATS.include?(cat)
    seeders = t["seeders"].to_i
    next if seeders < SEEDED_MIN_SEEDERS
    name = t["name"].to_s
    next if name.empty?
    next unless not_dubbed?(name)
    res = resolution(name)
    next if res.nil? || res > MAX_RES
    hash = t["info_hash"].to_s.downcase
    next unless hash.match?(/\A[a-f0-9]{40}\z/)

    imdb = t["imdb"].to_s
    key = if imdb.match?(/\Att\d+\z/)
            kind = %w[205 208].include?(cat) ? "tv" : "movie"
            "#{kind}:#{imdb}"
          else
            "release:#{hash}"
          end
    next if state.tracked?(key)

    next unless imdb.match?(/\Att\d+\z/)
    type = cat == "207" ? "movie" : "series"
    meta = cinemeta_meta(type, imdb)
    next if content_exclusion(meta)
    year = metadata_year(meta)
    next if type == "movie" && !movie_year_allowed?(year)
    next if skip_listed?(Target.new(title: meta["name"], imdb_id: imdb))
    size_mb = (t["size"].to_i / 1024 / 1024)
    out << {
      key:      key,
      title:    meta["name"] || name,
      year:     year,
      seeds:    seeders,
      res:      res,
      size_mib: size_mb,
      stream: {
        "title"    => release_label(name, t["size"], seeders),
        "infoHash" => hash,
        "seeds"    => seeders,
        "_res"     => res,
        "_seeds"   => seeders,
      },
    }
  end

  seen = {}
  out.sort_by { |c| -c[:seeds] }.reject { |c| seen[c[:key]] ? true : (seen[c[:key]] = true; false) }
end

def cached_metadata(url, ttl)
  cache = $metadata_cache ||= Cache.new(CACHE_DIR)
  key = "meta_#{Digest::SHA256.hexdigest(url)}"
  hit = cache.get(key, $offline ? 180 * 86_400 : ttl)
  return hit["data"] if hit && hit.key?("data")
  return nil if $offline
  data = http_json(url)
  cache.put(key, { "data" => data }) if data.is_a?(Hash)
  data || cache.get(key, 180 * 86_400)&.fetch("data", nil)
end

def title_tokens(text)
  utf8_text(text).unicode_normalize(:nfkd).downcase.gsub(/\p{Mn}/, "")
      .scan(/[\p{L}\p{N}]+/u)
end

def title_identity(text)
  title_tokens(text).join(" ")
end

def metadata_year(meta)
  year = (meta["releaseInfo"] || meta["year"] || meta["released"]).to_s[/\b(?:19|20)\d{2}\b/]
  year&.to_i
end

# Screen themes, not the identities of cast or crew.
def content_exclusion(meta)
  return "metadata unavailable" unless meta.is_a?(Hash)
  released = meta["released"].to_s
  if released.match?(/\A\d{4}-\d{2}-\d{2}/)
    date = Date.iso8601(released[0, 10]) rescue nil
    return "not yet released" if date && date > Date.today
  end
  genres = Array(meta["genres"] || meta["genre"]).map { |g| title_identity(g) }
  plot = [meta["description"], meta["overview"], meta["plot"], *Array(meta["keywords"]), *Array(meta["tags"])].compact.join(" ")
  return "insufficient content metadata" if genres.empty? && plot.strip.empty?
  return "horror/gore" if genres.any? { |g| g.match?(/\b(?:horror|gore|slasher|splatter)\b/) }
  return "children/family" if genres.any? { |g| g.match?(/\b(?:family|children|kids|preschool)\b/) }
  return "documentary" if genres.any? { |g| g.match?(/\b(?:documentary|documentaries|docuseries|docu series|nonfiction|non fiction)\b/) }
  return "biography" if genres.any? { |g| g.match?(/\b(?:biography|biographical|biopic|biographies)\b/) }
  # Screen descriptions of the film itself, not incidental plot details.
  themes = title_identity([plot, *genres].join(" "))
  return "documentary" if themes.match?(/\b(?:documentary film|documentary series|feature documentary|this documentary|a documentary about)\b/)
  return "biography" if themes.match?(/\b(?:biopic|biographical (?:film|drama|movie|portrait)|film biography|screen biography)\b/)
  text = title_identity([meta["name"], plot, *genres].compact.join(" "))
  return "horror/gore" if text.match?(/\b(?:gore|gory|body horror|graphic dismemberment|splatter film|slasher(?: film| killer)?)\b/)
  return "children/family" if text.match?(/\b(?:children s (?:film|movie|animation|series)|for (?:young children|kids|preschoolers)|preschool series|family friendly)\b/)
  return "LGBTQ themes" if text.match?(/\b(?:lgbtq?[a-z]*|queer|gay|lesbian|same sex (?:romance|love|relationship|couple)|homosexual(?:ity)?)\b/)
  rating = rt_scores([meta["id"]])[meta["id"]]
  floor = $min_rating || MIN_RT_RATING
  return "Tomatometer unavailable" if rating.nil? && $require_rating
  return "Tomatometer below #{floor}%" if rating && rating < floor
  nil
end

def cinemeta_search(type, query, year = nil)
  data = cached_metadata("#{CINEMETA}/catalog/#{type}/top/search=#{CGI.escape(query)}.json", SEARCH_TTL)
  hits = Array(data && data["metas"]).select do |m|
    m.is_a?(Hash) && m["id"].to_s.match?(/\Att\d+\z/) &&
      title_identity(m["name"]) == title_identity(query) &&
      (!year || metadata_year(m) == year)
  end.uniq { |m| m["id"] }
  if hits.size > 1
    say("cinemeta0: ambiguous #{query}; use an IMDb ID or title (year)")
    return nil
  end
  hits.first
end

def cinemeta_meta(type, id)
  return nil unless id.to_s.match?(/\Att\d+\z/)
  data = cached_metadata("#{CINEMETA}/meta/#{type}/#{id}.json", META_TTL)
  meta = data && data["meta"]
  meta if meta.is_a?(Hash) && meta["id"] == id
end

def resolve_imdb_id(title, year, kind)
  type = kind == :tv ? "series" : "movie"
  hit  = cinemeta_search(type, title, year)
  hit && hit["id"]
end

def process_movie(target, state, cache, dry_run, stats, stall)
  if skip_listed?(target)
    say("mov0: skip #{target.title} (skip list)")
    return nil
  end
  if target.imdb_id.nil?
    target.imdb_id = resolve_imdb_id(target.title, target.year, :movie)
    return nil if target.imdb_id.nil?
  end
  meta = cinemeta_meta("movie", target.imdb_id)
  target.year = metadata_year(meta || {})
  reason = if !movie_year_allowed?(target.year)
             "movie year outside #{MIN_MOVIE_YEAR}–#{Time.now.year} or unknown"
           else
             content_exclusion(meta)
           end
  if reason
    say("mov0: skip #{target.title} (#{reason})")
    bump(stats, :skipped)
    return nil
  end
  key = "movie:#{target.imdb_id}"

  if state.tracked?(key)
    say((dry_run ? "skip:  " : "mov0: skip ") + "#{target.title} #{skip_reason(state.status(key))}")
    bump(stats, :skipped)
    return nil
  end

  streams = find_streams(:movie, target.imdb_id, target.title, year: target.year)
  if dry_run
    picks = best_streams(streams)
    if picks.empty?
      say("skip:  #{target.title} — no 480/720p streams")
      bump(stats, :no_streams)
    else
      say("would: #{target.title} (#{target.year}) — #{picks.first['_res']}p, #{size_mib(picks.first['title'])}MB")
      bump(stats, :would)
    end
    return nil
  end

  result = attempt_streams(streams, key, target.title, target.year, ROOT, state, cache, stall: stall)
  case result
  when :ok then bump(stats, :downloaded)
  when :no_streams
    bump(stats, :no_streams)
    say("indexer0: no streams #{target.title}, retry in 7 days")
    state.mark_unavailable(key, { "title" => target.title, "year" => target.year })
  when :interrupted, :busy
    nil
  when :disk_full
    bump(stats, :disk_full)
    return :disk_full
  when :skipped_by_user
    bump(stats, :skipped_by_user)
    say("mov0: skipped #{target.title} by user")
  else
    bump(stats, :failed)
    say("aria0: failed #{target.title}")
    state.mark_failed(key, { "title" => target.title, "year" => target.year, "reason" => "download failed" })
  end
  nil
end

def process_series(target, state, cache, dry_run, stats, stall)
  if skip_listed?(target)
    say("mov0: skip #{target.title} (skip list)")
    return nil
  end
  if target.imdb_id.nil?
    target.imdb_id = resolve_imdb_id(target.title, target.year, :tv)
    return nil if target.imdb_id.nil?
  end

  if (reason = content_exclusion(cinemeta_meta("series", target.imdb_id)))
    say("mov0: skip #{target.title} (#{reason})")
    bump(stats, :skipped)
    return nil
  end
  episodes = series_episodes(target.imdb_id)
  if episodes.empty?
    say("cinemeta0: no episodes #{target.title}")
    bump(stats, :no_streams)
    return nil
  end

  season = episodes.first["season"].to_i
  say("mov0: #{target.title} S#{season} #{episodes.size} eps")

  episodes.each do |ep|
    break if $exit_now || $stop_new
    sn = ep["season"].to_i
    en = ep["episode"].to_i
    key = "tv:#{target.imdb_id}:#{sn}:#{en}"
    label = "#{target.title} S#{format('%02d', sn)}E#{format('%02d', en)}"

    if state.tracked?(key)
      say("mov0: skip #{label} #{skip_reason(state.status(key))}")
      bump(stats, :skipped)
      reset_skip
      next
    end

    streams = find_streams(:series, "#{target.imdb_id}:#{sn}:#{en}", target.title,
                           year: target.year, season: sn, episode: en)
    if dry_run
      picks = best_streams(streams)
      if picks.empty?
        say("skip:  #{label} — no 480/720p streams")
        bump(stats, :no_streams)
      else
        say("would: #{label} — #{picks.first['_res']}p, #{size_mib(picks.first['title'])}MB")
        bump(stats, :would)
      end
      next
    end

    result = attempt_streams(streams, key, target.title, target.year, ROOT, state, cache,
                             season: sn, episode: en, stall: stall)
    case result
    when :ok
      bump(stats, :downloaded)
    when :no_streams
      bump(stats, :no_streams)
      say("indexer0: no streams #{label}")
      state.mark_failed(key, { "title" => label, "year" => target.year, "reason" => "no streams" })
    when :interrupted, :busy
      nil
    when :disk_full
      bump(stats, :disk_full)
      return :disk_full
    when :skipped_by_user
      bump(stats, :skipped_by_user)
      say("mov0: skipped #{label} by user")
      reset_skip
    else
      bump(stats, :failed)
      say("aria0: failed #{label}")
      state.mark_failed(key, { "title" => label, "year" => target.year, "reason" => "download failed" })
    end
  end
  nil
end

def process_seeded_one(c, state, cache, dry_run, stats, stall)
  key   = c[:key]
  label = c[:title][0, 70]
  if key.start_with?("direct:")
    hit = cinemeta_search("movie", c[:title], c[:year]) if movie_year_allowed?(c[:year])
    meta = cinemeta_meta("movie", hit["id"]) if hit
    reason = if !movie_year_allowed?(metadata_year(meta || {}))
               "direct input requires an identifiable movie from #{MIN_MOVIE_YEAR} or later (title (year))"
             else
               content_exclusion(meta)
             end
    if reason || skip_listed?(Target.new(title: c[:title], imdb_id: hit && hit["id"]))
      say("mov0: skip #{label} (#{reason || 'skip list'})")
      bump(stats, :skipped)
      return nil
    end
    key = "movie:#{hit['id']}"
  end
  if (key.start_with?("direct:", "movie:", "release:") && !movie_year_allowed?(c[:year]))
    say("mov0: skip #{label} (movie year outside #{MIN_MOVIE_YEAR}–#{Time.now.year} or unknown; direct inputs need title (year))")
    bump(stats, :skipped)
    return nil
  end

  return nil if state.tracked?(key)

  if dry_run
    say("would: #{label} [direct input]") if c[:stream]["_direct"]
    say("would: #{label} — #{c[:res]}p, #{c[:size_mib]}MB, #{c[:seeds]} seeds [seeded]") unless c[:stream]["_direct"]
    bump(stats, :would)
    return nil
  end

  result = attempt_streams([c[:stream]], key, c[:title], c[:year], ROOT, state, cache, stall: stall)
  case result
  when :ok
    bump(stats, :downloaded)
  when :interrupted, :busy
    nil
  when :disk_full
    bump(stats, :disk_full)
    return :disk_full
  when :skipped_by_user
    bump(stats, :skipped_by_user)
    say("mov0: skipped #{label} by user")
  else
    bump(stats, :failed)
    say("aria0: failed #{label}")
    state.mark_failed(key, { "title" => c[:title], "year" => c[:year], "reason" => "download failed" })
  end
  nil
end

def run_pool(items, jobs)
  $pool_running = true
  queue = Queue.new
  items.each { |it| queue << it }
  queue.close
  jobs = [[jobs, 1].max, items.size].min
  workers = Array.new(jobs) do |i|
    Thread.new do
      Thread.current[:unit] = i
      while (item = queue.pop)
        break if $exit_now || $stop_new
        reset_skip
        begin
          $stop_new = true if item[:run].call == :disk_full
        rescue StandardError => e
          say("mov0: error processing #{item[:label]}: #{e.class}: #{e.message}")
        end
      end
    end
  end
  workers.each(&:join)
ensure
  $pool_running = false
end

DIRECT_RE = /\A(?<title>.+?)=(?<target>magnet:\S+|[a-fA-F0-9]{40}|[A-Za-z2-7]{32}|https?:\/\/\S+)\z/

def direct_item(arg)
  m = DIRECT_RE.match(arg) or return nil
  title  = m[:title].strip
  target = m[:target]
  year   = title[/\((\d{4})\)/, 1]&.to_i
  title  = title.sub(/\s*\(\d{4}\)\s*\z/, "")
  stream = { "title" => title, "_direct" => true }
  if target.start_with?("http")
    stream["_uri"]     = target
    stream["infoHash"] = Digest::SHA1.hexdigest(target)
  else
    stream["url"] = target if target.start_with?("magnet:")
    stream["infoHash"] = normalize_hash(target) || infohash(stream)
    return nil unless stream["infoHash"]
  end
  res = target[/(\d{3,4})p/, 1] || title[/(\d{3,4})p/, 1]
  stream["_res"] = res&.to_i
  { key: "direct:#{stream['infoHash']}", title: title, year: year, stream: stream }
end

def resolve_query(query)
  if query.match?(/\Att\d{5,}\z/)
    %w[movie series].each do |type|
      meta = cinemeta_meta(type, query) or next
      yr = meta["releaseInfo"].to_s[0, 4].to_i
      return [Target.new(title: meta["name"], year: yr.positive? ? yr : nil,
                         media_type: type == "series" ? :tv : :movie, imdb_id: query)]
    end
    say("cinemeta0: #{query} not found")
    return []
  end
  year = query[/\s*\((\d{4})\)\s*\z/, 1]&.to_i
  query = query.sub(/\s*\(\d{4}\)\s*\z/, "") if year
  out = []
  %w[movie series].each do |type|
    hit = cinemeta_search(type, query, year)
    next unless hit
    yr = hit["releaseInfo"].to_s[0, 4].to_i
    out << Target.new(title: hit["name"], year: yr.positive? ? yr : nil,
                      media_type: type == "series" ? :tv : :movie, imdb_id: hit["id"])
  end
  out
end

def cmd_status(state, cache)
  c = state.counts
  say("mov0: mov #{MOV_VERSION} at #{ROOT} free #{free_gb.round(1)}GB")
  say("state: #{c[:total]} tracks: #{c[:completed]} completed (#{(c[:bytes] / 1024.0**3).round(1)}GB), #{c[:skipped]} skipped, #{c[:failed]} failed")
  completed = state.all.select { |_, v| v["status"] == "completed" }.values
  if completed.any?
    last = completed.max_by { |v| v["at"].to_s }
    date = Time.parse(last["at"]).strftime("%Y-%m-%d") rescue "?"
    say("state: last #{last['title']} (#{date})")
  end
  say("mov0: defaults source #{DEFAULT_SOURCE}, jobs #{DEFAULT_JOBS}, prefer 480/720p")
  say("mov0: stall #{DEFAULT_STALL}s, dead #{DEFAULT_DEAD}s")
  say("tracker0: cache #{cache.get('trackers', TRACKER_TTL) ? 'present' : 'missing (--check-trackers)'}")
end

def cmd_list(state)
  if state.all.empty?
    say("db0: no downloads")
    return
  end
  c = state.counts
  say("db0: #{c[:total]} tracks #{c[:completed]} completed #{c[:skipped]} skipped #{c[:failed]} failed")
  state.all.sort_by { |_, v| v["at"].to_s }.reverse.each do |_, v|
    mb   = (v["size"].to_i / (1024.0**2)).round
    date = Time.parse(v["at"]).strftime("%Y-%m-%d") rescue "?"
    tag  = case v["status"]
           when "skipped", "interrupted" then " [skipped]"
           when "failed"                 then " [failed]"
           when "incomplete"             then " [incomplete]"
           else                               ""
           end
    tag += " [missing]" if v["status"] == "completed" && !File.exist?(v["path"].to_s)
    say("db0: #{date} #{mb}MB #{v['title']}#{tag}")
  end
end

def cmd_check(state, cache)
  say("mov0: ruby #{RUBY_VERSION}")
  say("mov0: aria2c #{Open3.capture2e('which', 'aria2c')[1].success? ? 'ok' : 'missing'}")
  say("mov0: dest #{ROOT} #{File.writable?(ROOT) ? 'writable' : 'NOT WRITABLE'}")
  say("disk0: free #{free_gb.round(1)}GB")
  say("mov0: defaults source #{DEFAULT_SOURCE}, jobs #{DEFAULT_JOBS}, prefer 480/720p")
  say("mov0: stall #{DEFAULT_STALL}s, dead #{DEFAULT_DEAD}s, progress percent")
  c = state.counts
  say("db0: #{c[:completed]} completed #{c[:skipped]} skipped #{c[:failed]} failed")
  say("tracker0: #{TRACKERS.size} configured")
  cached = cache.get("trackers", TRACKER_TTL)
  say("tracker0: cache #{cached ? "#{cached['list'].size} entries" : 'missing (--check-trackers)'}")
end

def probe_udp(host, port, timeout: 1.5)
  sock = UDPSocket.new
  sock.connect(host, port)
  txn   = rand(2**32)
  magic = 0x41727101980
  sock.send([magic, 0, txn].pack("Q> N N"), 0)
  return false unless IO.select([sock], nil, nil, timeout)
  data, = sock.recvfrom(1024)
  return false if data.bytesize < 16
  action, rtxn = data.unpack("N N")
  action.zero? && rtxn == txn
rescue StandardError
  false
ensure
  begin
    sock&.close
  rescue StandardError
    nil
  end
end

def probe_http(uri, timeout: 1.5)
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                  open_timeout: timeout, read_timeout: timeout) do |h|
    res = h.get(uri.request_uri)
    res.code.to_i < 500
  end
rescue StandardError
  false
end

def cmd_check_trackers(cache)
  say("tracker0: probing #{TRACKERS.size} endpoints")
  results = []
  lock    = Mutex.new
  TRACKERS.select(&:ascii_only?).each_slice(10) do |batch|
    batch.map do |u|
      Thread.new do
        uri = begin
          URI.parse(u)
        rescue StandardError
          nil
        end
        lat = 9999.0
        if uri
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          ok = case uri.scheme
               when "udp"           then probe_udp(uri.host, uri.port)
               when "http", "https" then probe_http(uri)
               else                      false
               end
          lat = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round(1) if ok
        end
        lock.synchronize { results << [u, lat] }
      end
    end.each(&:join)
  end
  alive = results.select { |_, lat| lat < 9999.0 }
  if alive.empty?
    say("tracker0: no reachable trackers (bundled list unchanged)")
    return
  end
  sorted = alive.sort_by { |_, lat| lat }.map(&:first)
  cache.put("trackers", { "list" => sorted })
  say("tracker0: #{alive.size}/#{results.size} reachable, cached 7d")
  sorted.first(10).each_with_index { |u, i| say("tracker0: ##{i + 1} #{u}") }
end

def cmd_prune(state, days:, yes:)
  cutoff  = Time.now.utc - days * 86_400
  victims = state.all.select do |_, v|
    next false unless v["status"] == "completed" && v["path"] && File.file?(v["path"])
    next false unless File.realpath(v["path"]).start_with?(File.realpath(ROOT) + File::SEPARATOR)
    at = begin
      Time.parse(v["at"].to_s)
    rescue StandardError
      Time.now.utc
    end
    at < cutoff
  end

  bytes = victims.sum { |_, v| File.size(v["path"]) rescue 0 }
  if victims.empty?
    say("prune0: no completed files older than #{days}d")
  elsif !yes
    say("prune0: would delete #{victims.size} files (#{(bytes / 1024.0**3).round(1)}GB)")
    say("prune0: re-run with --prune --yes to delete")
  else
    victims.each do |key, v|
      FileUtils.rm_f(v["path"])
      state.delete(key)
      say("prune0: removed #{File.basename(v['path'])}")
    end
    say("prune0: freed #{(bytes / 1024.0**3).round(1)}GB")
  end

  unless yes
    say("prune0: staging and logs unchanged (preview)")
    return
  end
  staged = 0
  live = live_aria2_dirs
  Dir.glob(File.join(STAGING, "*")).each do |d|
    next unless live && File.directory?(d) && !File.symlink?(d)
    next if live.include?(File.expand_path(d))
    next if newest_mtime(d) > Time.now - STAGING_TTL
    FileUtils.rm_rf(d)
    staged += 1
  end
  say("prune0: removed #{staged} stale staging dirs") if staged.positive?

  logs = 0
  Dir.glob(File.join(ARIA2_LOGS, "*.log")).each do |f|
    next unless Time.now - File.mtime(f) > ARIA2_LOG_TTL
    File.delete(f) rescue next
    logs += 1
  end
  say("prune0: removed #{logs} old aria2 logs") if logs.positive?

  say("disk0: free #{free_gb.round(1)}GB")
end

# ---------------------------------------------------------------------------
# Taste discovery (--source taste, the default).
#
#   1. Candidates: Wikidata festival films (won or competed at the festivals
#      below), recent films by directors already in the watch history, the
#      hand-kept prestige list and ~/.config/mov/wishlist.
#   2. Filters: already seen/skipped/tracked, black-and-white (Wikidata P462),
#      movies before 2022, including wishlist and prestige entries.
#   3. Rank a bounded shortlist using cached film metadata and weighted taste notes.
#   4. Recommend directly, or check availability in batches until the quota is met.
# ---------------------------------------------------------------------------

TASTE_PATH    = File.join(CFG_DIR, "taste.md")
WISHLIST_PATH = File.join(CFG_DIR, "wishlist")
MOVSH_STATE   = File.join(Dir.home, "mov-sh-state")
WIKIDATA_SPARQL = "https://query.wikidata.org/sparql"
WIKIDATA_TTL  = 86_400
BLACK_AND_WHITE = "Q838368"

FESTIVALS = {
  "Q42369" => "Cannes", "Q130871" => "Berlinale", "Q49024" => "Venice",
  "Q502053" => "Locarno", "Q189887" => "Sundance", "Q390018" => "TIFF",
  "Q332869" => "Karlovy Vary", "Q622423" => "San Sebastián",
}.freeze

def sparql(query, tries: 2)
  return [] if $offline
  uri = URI(WIKIDATA_SPARQL)
  tries.times do |n|
    res = begin
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 25) do |h|
        h.post(uri.path, URI.encode_www_form(query: query),
               "User-Agent" => UA, "Accept" => "application/sparql-results+json",
               "Content-Type" => "application/x-www-form-urlencoded")
      end
    rescue StandardError
      nil
    end
    if res&.code == "200"
      rows = JSON.parse(res.body).dig("results", "bindings") rescue nil
      return rows if rows.is_a?(Array)
    end
    sleep(2 * (n + 1)) if n + 1 < tries
  end
  say("wikidata0: unavailable after #{tries} tries")
  []
end

# Only explicitly identified critics' Tomatometer statements count.
# Wikidata scores can be stale; never substitute audience or IMDb scores.
def rt_percentage(value)
  match = /\A\s*(\d{1,3})\s*%\s*\z/.match(value.to_s)
  number = match && match[1].to_i
  number if number&.between?(0, 100)
end

def rt_scores(ids)
  ids = ids.select { |id| id.to_s.match?(/\Att\d{5,}\z/) }.uniq
  return {} if ids.empty?
  RT_LOCK.synchronize do
    memory = $rt_scores ||= {}
    cache = $metadata_cache ||= Cache.new(CACHE_DIR)
    pending = ids.reject do |id|
      next true if memory.key?(id)
      entry = cache.get("rt_#{id}", $offline ? 180 * 86_400 : RT_TTL)
      score = entry && entry["score"]
      next false unless score.is_a?(Integer) && score.between?(0, 100)
      memory[id] = score
      true
    end
    unless $offline
      pending.each_slice(50) do |batch|
        break if $exit_now
        rows = sparql(<<~Q, tries: 1)
          SELECT ?id ?score ?date WHERE {
            VALUES ?id { #{batch.map { |id| '"' + id + '"' }.join(' ')} }
            ?film wdt:P345 ?id; p:P444 ?statement .
            ?statement ps:P444 ?score; pq:P459 wd:Q108403393;
                       wikibase:rank ?rank .
            FILTER(?rank != wikibase:DeprecatedRank)
            OPTIONAL { ?statement pq:P585 ?date }
          } ORDER BY DESC(?date)
        Q
        batch.each { |id| memory[id] = nil }
        rows.each do |row|
          id = row.dig("id", "value")
          score = rt_percentage(row.dig("score", "value"))
          next unless batch.include?(id) && score && memory[id].nil?
          memory[id] = score
          cache.put("rt_#{id}", { "score" => score, "date" => row.dig("date", "value") })
        end
        # Keep a previously fetched score available during provider failures.
        batch.each do |id|
          next unless memory[id].nil?
          old = cache.get("rt_#{id}", 180 * 86_400)
          score = old && old["score"]
          memory[id] = score if score.is_a?(Integer) && score.between?(0, 100)
        end
      end
    end
    ids.to_h { |id| [id, memory[id]] }
  end
end

def qid(binding, key) = binding.dig(key, "value").to_s.split("/").last

def seen_ids(state, recommend: false)
  ids = Set.new
  [File.join(MOVSH_STATE, "history"), File.join(MOVSH_STATE, "skip"), SKIP_PATH].each do |p|
    next unless File.exist?(p)
    File.foreach(p) { |l| id = l[/tt\d{5,}/]; ids << id if id }
  end
  state.all.each do |key, value|
    next unless key.start_with?("movie:")
    id = key[/tt\d{5,}/] or next
    tracked = recommend ? %w[completed skipped interrupted].include?(value["status"]) : state.tracked?(key)
    ids << id if tracked
  end
  ids
end

def watched_ids(state)
  ids = []
  h = File.join(MOVSH_STATE, "history")
  ids.concat(File.readlines(h, chomp: true).grep(/\Att\d+\z/)) if File.exist?(h)
  state.all.each { |k, v| ids << k[/tt\d+/] if v["status"] == "completed" && k.start_with?("movie:") }
  ids.compact.uniq
end

def wd_label(b, key)
  label = b.dig(key, "value").to_s.strip
  label.match?(/\AQ\d+\z/) || label.empty? ? nil : label
end

def wd_title(b) = wd_label(b, "filmLabel")

def wikidata_festival_films(cache)
  if (c = cache.get("wd_festival_v4_#{discovery_since}", $offline ? 180 * 86_400 : WIKIDATA_TTL))
    return c["films"]
  end
  return [] if $offline
  awards = sparql(<<~Q).to_h { |b| [qid(b, "award"), FESTIVALS[qid(b, "fest")]] }
    SELECT DISTINCT ?award ?fest WHERE {
      VALUES ?fest { #{FESTIVALS.keys.map { |f| "wd:#{f}" }.join(' ')} }
      ?award wdt:P1027 ?fest .
    }
  Q
  since = discovery_since
  films = {}
  awards.keys.each_slice(10) do |batch|
    rows = sparql(<<~Q)
      SELECT ?imdb ?date ?prop ?award ?awardLabel ?filmLabel ?colour WHERE {
        VALUES ?award { #{batch.map { |a| "wd:#{a}" }.join(' ')} }
        VALUES ?prop { wdt:P166 wdt:P1411 }
        ?film ?prop ?award ; wdt:P577 ?date ; wdt:P345 ?imdb .
        FILTER(?date >= "#{since}-01-01T00:00:00Z"^^xsd:dateTime)
        FILTER NOT EXISTS { ?film wdt:P577 ?early . FILTER(?early < "#{since}-01-01T00:00:00Z"^^xsd:dateTime) }
        OPTIONAL { ?film wdt:P462 ?colour }
        SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
      }
    Q
    rows.each do |b|
      id = b.dig("imdb", "value")
      f  = films[id] ||= {
        "imdb" => id, "title" => wd_title(b),
        "year" => b.dig("date", "value").to_s[0, 4].to_i,
        "why" => [], "bw" => false, "score" => 0,
      }
      won   = b.dig("prop", "value").to_s.end_with?("P166")
      fest  = awards[qid(b, "award")]
      award = wd_label(b, "awardLabel")
      verb  = won ? "won" : "competed for"
      f["why"] |= [award ? "#{verb} #{award} (#{fest})" : "#{verb} a #{fest} award"]
      f["score"] = [f["score"], won ? 3 : 2].max
      f["bw"] ||= qid(b, "colour") == BLACK_AND_WHITE
      f["year"] = [f["year"], b.dig("date", "value").to_s[0, 4].to_i].min
    end
    sleep 1
  end
  cache.put("wd_festival_v4_#{discovery_since}", { "films" => films.values }) unless films.empty?
  films.values
end

def wikidata_director_films(cache, watched)
  key = "wd_directors_v4_#{discovery_since}_#{Digest::SHA1.hexdigest(watched.sort.join)[0, 10]}"
  hit = cache.get(key, $offline ? 180 * 86_400 : WIKIDATA_TTL)
  return hit["films"] if hit
  return [] if $offline || watched.empty?

  since = discovery_since
  films = {}
  watched.each_slice(80) do |batch|
    rows = sparql(<<~Q)
      SELECT DISTINCT ?imdb ?date ?filmLabel ?dirLabel ?colour WHERE {
        VALUES ?seenImdb { #{batch.map { |i| "\"#{i}\"" }.join(' ')} }
        ?seen wdt:P345 ?seenImdb ; wdt:P57 ?dir .
        ?film wdt:P57 ?dir ; wdt:P31 wd:Q11424 ; wdt:P345 ?imdb ; wdt:P577 ?date .
        FILTER(?date >= "#{since}-01-01T00:00:00Z"^^xsd:dateTime)
        FILTER NOT EXISTS { ?film wdt:P577 ?early . FILTER(?early < "#{since}-01-01T00:00:00Z"^^xsd:dateTime) }
        OPTIONAL { ?film wdt:P462 ?colour }
        SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
      }
    Q
    rows.each do |b|
      id = b.dig("imdb", "value")
      f  = films[id] ||= {
        "imdb" => id, "title" => wd_title(b),
        "year" => b.dig("date", "value").to_s[0, 4].to_i,
        "why" => [], "bw" => false, "score" => 1,
      }
      dir = wd_label(b, "dirLabel")
      f["why"] |= [dir ? "new film by #{dir}, whose work is in your history" : "new film by a director in your history"]
      f["bw"] ||= qid(b, "colour") == BLACK_AND_WHITE
    end
    sleep 1
  end
  cache.put(key, { "films" => films.values }) unless films.empty?
  films.values
end

def listed_films
  out = []
  pf = File.join(MOVSH_STATE, "prestige")
  if File.exist?(pf)
    File.foreach(pf) do |l|
      yr, id, note = l.chomp.split("\t", 3)
      if id.to_s.start_with?("tt")
        out << { "imdb" => id, "title" => note.to_s.sub(/\s*\(.*\z/, ""), "year" => yr.to_i,
                 "why" => ["on your prestige list: #{note}"], "bw" => false, "score" => 3 }
      end
    end
  end
  if File.exist?(WISHLIST_PATH)
    File.foreach(WISHLIST_PATH) do |l|
      id = l.sub(/#.*/, "")[/tt\d{5,}/] or next
      out << { "imdb" => id, "title" => nil, "year" => nil,
               "why" => ["on your wishlist"], "bw" => false, "score" => 4 }
    end
  end
  out
end

def availability(imdb_id)
  picks = torrentio_streams("movie", imdb_id).filter_map { |s| score_stream(s) }
  best  = picks.max_by { |s| s["_score"] }
  return nil unless best && best["_seeds"].to_i >= 3
  { "seeds" => best["_seeds"], "res" => best["_res"], "mb" => size_mib(best["title"]) }
end

def taste_terms(path = TASTE_PATH)
  return {} unless File.exist?(path)
  File.readlines(path, chomp: true).each_with_object({}) do |line, terms|
    text = line.strip.downcase
    next if text.empty? || text.start_with?("#")
    weight = 3
    if (match = text.match(/\A([+-]\d+)\s+(.+)\z/))
      weight = match[1].to_i.clamp(-10, 10)
      text = match[2]
    elsif text.match?(/\A(no|avoid|not|dislike)\s+/)
      weight = -5
      text = text.sub(/\A(no|avoid|not|dislike)\s+/, "")
    end
    phrase = title_identity(text)
    terms[phrase] = weight unless phrase.empty?
  end
end

def taste_rank(cands, want, terms: taste_terms)
  scored = cands.map do |c|
    meta = c["meta"] || {}
    fields = [c["title"], *Array(c["why"]), meta["description"],
              *Array(meta["genres"] || meta["genre"]), *Array(meta["director"]),
              *Array(meta["cast"]), meta["country"]]
    text = " #{title_identity(fields.compact.join(' '))} "
    matches = terms.select { |phrase, _| text.include?(" #{phrase} ") }
    score = c["score"].to_f * 2 + matches.values.sum
    rating = c["rt_score"]
    score += (rating - 75) / 5.0 if rating
    score += 0.5 if c["year"].to_i >= Time.now.year - 2
    arrival = stream_date(c["stream_date"])
    score += 8.0 * (1 - (Date.today - arrival).to_f / ($stream_days || STREAM_DAYS)) if arrival
    reasons = matches.sort_by { |term, weight| [-weight, term] }.first(4)
    reason = reasons.map { |term, weight| "#{term} (#{format('%+d', weight)})" }
    reason += [rating ? "Tomatometer #{rating}%" : "Tomatometer unknown"] if c.key?("rt_score")
    reason += Array(c["why"]).first(2)
    [c, score, reason.join(", ")]
  end
  scored.sort_by { |c, score, _| [stream_date(c["stream_date"]) ? 0 : 1, -score, c["imdb"].to_s] }.first(want)
        .map { |c, _, reason| [c, reason.empty? ? "metadata match" : reason] }
end

def parallel_each(items, workers: 4)
  queue = Queue.new
  items.each { |item| queue << item }
  queue.close
  Array.new([workers, items.size].min) do
    Thread.new do
      while (item = queue.pop)
        break if $exit_now
        yield item
      end
    end
  end.each(&:value)
end

def enrich_films(films)
  parallel_each(films) do |film|
    meta = cinemeta_meta("movie", film["imdb"])
    next unless meta
    film["meta"] = meta
    film["title"] = meta["name"] || film["title"]
    film["year"] = metadata_year(meta)
  end
end

# Catalog arrivals are separate from theatrical release dates. GoodWatch's
# public calendar covers 14 days; keep observations for the rolling window.
def stream_date(value, today: Date.today)
  date = Date.iso8601(value.to_s)
  date if date <= today && date >= today - ($stream_days || STREAM_DAYS)
rescue ArgumentError
  nil
end

def html_text(value)
  CGI.unescapeHTML(utf8_text(value).gsub(/<[^>]*>/m, ' ')).gsub(/\s+/, ' ').strip
end

def catalog_date(label, today)
  label = label.sub(/\s+\d+\z/, '')
  return today if label == 'Today'
  return today - 1 if label == 'Yesterday'
  match = label.match(/\b(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2})\b/)
  return unless match
  date = Date.new(today.year, Date::MONTHNAMES.index(match[1]), match[2].to_i)
  date > today ? date << 12 : date
rescue ArgumentError
  nil
end

# Returns nil when the page is not a calendar: an empty month and a blocked
# fetch must not look the same to the caller.
def parse_streaming_calendar(html, region, today: Date.today)
  return nil unless html.is_a?(String)
  html = utf8_text(html)
  # Limit parsing to the dated calendar, not the site's recommendations.
  start = html.match(/<h2\b[^>]*>\s*Day by day\s*<\/h2>/i)
  return nil unless start
  body = html[start.end(0)..].split(/<h2\b/i, 2).first
  rows = {}
  date = nil
  body.scan(/<h3\b[^>]*>(.*?)<\/h3>|<a\b([^>]*)>(.*?)<\/a>/im) do |heading, attrs, inner|
    if heading
      date = catalog_date(html_text(heading), today)
      next
    end
    next unless date && stream_date(date.iso8601, today: today)
    href = attrs[/\bhref\s*=\s*["']([^"']+)["']/i, 1]
    next unless href&.match?(%r{\A(?:https://goodwatch\.app)?/movie/\d+-[^/?#]+/?\z})
    labels = [attrs[/\baria-label\s*=\s*["']([^"']+)["']/i, 1], attrs[/\btitle\s*=\s*["']([^"']+)["']/i, 1], inner[/\balt\s*=\s*["']([^"']+)["']/i, 1], inner]
    match = labels.compact.filter_map { |s| html_text(s).match(/\A(.+?)\s*\(((?:19|20)\d{2})\)/) }.first
    match ||= html_text(inner).match(/\A(.+?)\s*((?:19|20)\d{2})(?:\s|\z)/)
    next unless match && movie_year_allowed?(match[2].to_i)
    title = match[1].strip
    next if title.empty?
    key = [title_identity(title), match[2].to_i]
    rows[key] ||= { 'title' => title, 'year' => match[2].to_i, 'stream_date' => date.iso8601, 'regions' => [region] }
  end
  rows.values
end

def recent_streaming_films(cache)
  key = 'streaming_arrivals_v1'
  old = cache.get(key, 180 * 86_400) || {}
  rows = Array(old['rows']).select { |r| r.is_a?(Hash) && stream_date(r['stream_date']) }
  if !$offline && !cache.get('streaming_refresh_v1', 12 * 3600)
    fresh = []
    parsed = 0
    regions = %w[no us]
    regions.each do |region|
      break if $exit_now
      html = http_get("#{GOODWATCH}/new/#{region}", retries: 1,
                      headers: { "Cookie" => GOODWATCH_COOKIE })
      got = parse_streaming_calendar(html, region.upcase)
      if got.nil?
        say("streaming0: #{region.upcase} calendar unavailable")
        next
      end
      parsed += 1
      say("streaming0: #{region.upcase} #{got.size} dated movie arrivals")
      fresh.concat(got)
    end
    # A failed or changed page never destroys previously collected arrivals.
    if fresh.any?
      merged = {}
      (rows + fresh).each do |r|
        k = [title_identity(r['title']), r['year']]
        if (prior = merged[k])
          prior['stream_date'] = [prior['stream_date'], r['stream_date']].min
          prior['regions'] = Array(prior['regions']) | Array(r['regions'])
        else
          merged[k] = r.dup
        end
      end
      rows = merged.values
      cache.put(key, { 'rows' => rows })
    end
    cache.put('streaming_refresh_v1', { 'ok' => true }) if parsed == regions.size
  end
  candidates = rows.sort_by { |r| r['stream_date'] }.reverse.first(DISCOVER_PROBE)
  results = []
  parallel_each(candidates, workers: 4) do |row|
    hit = cinemeta_search('movie', row['title'], row['year'])
    next unless hit
    date = row['stream_date']
    film = { 'imdb' => hit['id'], 'title' => hit['name'], 'year' => row['year'],
             'stream_date' => date, 'why' => ["streaming arrival #{date} (#{Array(row['regions']).join('/')})"],
             'score' => 3, 'bw' => false }
    LOCK.synchronize { results << film }
  end
  say("streaming0: #{results.size} matched films within #{$stream_days || STREAM_DAYS} days")
  results
end

def discover_by_taste(cache, state, want: TASTE_WANT, recommend: false)
  seen  = seen_ids(state, recommend: recommend)
  since = discovery_since
  pool  = {}
  sources = {
    "streaming" => -> { recent_streaming_films(cache) },
    "festival" => -> { wikidata_festival_films(cache) },
    "director" => -> { wikidata_director_films(cache, watched_ids(state)) },
    "lists"    => -> { listed_films },
  }
  sources.each do |name, fetch|
    got = fetch.call
    say("wikidata0: #{got.size} #{name} films") if %w[festival director].include?(name)
    say("lists0: #{got.size} prestige/wishlist entries") if name == "lists"
    got.each do |f|
      next unless f["imdb"].to_s.match?(/\Att\d+\z/)
      cur = pool[f["imdb"]]
      if cur
        cur["why"]   |= f["why"]
        cur["score"] += f["score"]
        cur["bw"]    ||= f["bw"]
        cur["title"] ||= f["title"]
        cur["year"]  ||= f["year"]
        cur["stream_date"] ||= f["stream_date"]
      else
        pool[f["imdb"]] = f.dup
      end
    end
  end
  fresh = pool.values.reject { |f| seen.include?(f["imdb"]) }
  bw    = fresh.count { |f| f["bw"] }
  fresh = fresh.reject { |f| f["bw"] } unless $include_bw
  fresh = fresh.reject { |f| f["year"].to_i.positive? && !movie_year_allowed?(f["year"], since: since) }
  say("taste0: #{pool.size} candidates, #{fresh.size} unseen (#{bw} black-and-white#{ $include_bw ? " included" : " dropped"})")

  terms = taste_terms
  probe = taste_rank(fresh, DISCOVER_PROBE, terms: terms).map(&:first)
  enrich_films(probe)
  ratings = rt_scores(probe.filter_map { |film| film.dig("meta", "id") })
  probe.each { |film| film["rt_score"] = ratings[film["imdb"]] }
  say("rt0: #{ratings.values.compact.size}/#{probe.size} Tomatometer scores available")
  rejected = Hash.new(0)
  probed = probe.size
  probe.select! do |film|
    reason = if !movie_year_allowed?(film["year"], since: since) || film["title"].to_s.empty?
               "year/title"
             elsif skip_listed?(Target.new(title: film["title"], imdb_id: film["imdb"]))
               "skip list"
             else
               content_exclusion(film["meta"])
             end
    rejected[reason] += 1 if reason
    reason.nil?
  end
  if rejected.any?
    order  = rejected.sort_by { |reason, n| [-n, reason.downcase] }
    detail = order.map { |reason, n| "#{reason}: #{n}" }.join(", ")
    say("taste0: #{rejected.values.sum}/#{probed} filtered (#{detail})")
  end
  ranked = taste_rank(probe, probe.size, terms: terms)
  if recommend
    ranked.first(want).each do |film, reason|
      say("taste0: <#{film['title']}, #{film['year']}> #{film['imdb']} — #{reason}")
    end
    return []
  end
  # Only titles already ranked by taste enter the availability stage.
  selected = []
  ranked.each_slice(DISCOVERY_BATCH) do |batch|
    parallel_each(batch, workers: 4) do |film, _|
      film["avail"] = availability(film["imdb"])
    end
    selected.concat(batch.select { |film, _| film["avail"] })
    break if selected.size >= want || $exit_now
  end
  selected.first(want).map do |film, reason|
    say("taste0: <#{film['title']}, #{film['year']}> #{reason}")
    Target.new(title: film["title"], year: film["year"], media_type: :movie, imdb_id: film["imdb"],
               est_mb: film.dig("avail", "mb").to_i)
  end
end

# ---------------------------------------------------------------------------
# Helpers for explicit staging cleanup.
# ---------------------------------------------------------------------------

def live_aria2_dirs
  out, = Open3.capture2("ps", "-axo", "command=")
  out.lines.grep(/\baria2c\b/).filter_map { |l| l[/--dir=(\S+)/, 1] }
     .map { |d| File.expand_path(d) }.to_set
rescue StandardError
  nil
end

def newest_mtime(dir)
  times = Dir.glob(File.join(dir, "**", "*"), File::FNM_DOTMATCH).filter_map do |f|
    File.mtime(f)
  rescue StandardError
    nil
  end
  (times << File.mtime(dir)).max
end

def boot_banner(source, stall, jobs)
  say("mov #{MOV_VERSION} (GENERIC.MP) #1: #{Time.now.strftime('%a %b %e %H:%M:%S %Z %Y')}")
  say("    #{ENV['USER']}@#{Socket.gethostname.split('.').first}:#{ROOT}")
  say("ruby #{RUBY_VERSION} (#{RUBY_PLATFORM})")
  say("avail disk = #{free_gb.round(1)}GB, min free #{MIN_FREE_GB}GB")
  say("mov0 at root: source #{source}, jobs #{jobs}, stall #{stall}s, dead #{$dead_after}s")
  say("mov0: movies #{MIN_MOVIE_YEAR}+, prefer 480/720p, Ctrl-C skips and marks seen; Ctrl-\\ quits")
  say("taste0: no horror/gore, children/family, LGBTQ themes, documentaries or biographies; Tomatometer floor #{$min_rating || MIN_RT_RATING}%")
  say("disk0 at mov0: #{ROOT}")
  say("staging0 at disk0: #{STAGING}")
  jobs.times { |i| say("aria#{i} at mov0: aria2c rpc, dht, pex, lpd") }
  say("wikidata0 at mov0: query.wikidata.org") if %w[taste all].include?(source)
  say("apibay0 at mov0: #{APIBAY.sub(%r{\Ahttps?://}, '')}") if %w[seeded all].include?(source)
  say("torrentio0 at mov0: #{TORRENTIO.sub(%r{\Ahttps?://}, '')}")
  say("cinemeta0 at mov0: #{CINEMETA.sub(%r{\Ahttps?://}, '')}")
end

def run(argv)
  opts = {}
  OptionParser.new do |o|
    o.banner = "Usage: ruby mov.rb [titles...] [--source taste|seeded|all] [--jobs N]"
    o.on("--status")              { opts[:status] = true }
    o.on("--dry-run")             { opts[:dry_run] = true }
    o.on("--recommend", "Rank films only; no release lookups or downloads") { opts[:recommend] = true }
    o.on("--limit N", Integer, "Number of recommendations (default #{TASTE_WANT})") { |n| opts[:limit] = n }
    o.on("--stream-days N", Integer, "Recent streaming arrival window (default 90 days)") { |n| opts[:stream_days] = n }
    o.on("--years N", Integer, "Narrow discovery window (never before #{MIN_MOVIE_YEAR})") { |n| opts[:years] = n }
    o.on("--min-rating N", Integer, "Minimum known Tomatometer percentage (default #{MIN_RT_RATING}; 0 disables)") { |n| opts[:min_rating] = n }
    o.on("--require-rating", "Exclude films without a known Tomatometer score") { opts[:require_rating] = true }
    o.on("--include-bw", "Include black-and-white films") { opts[:include_bw] = true }
    o.on("--offline", "Use cached and local film metadata with --recommend") { opts[:offline] = true }
    o.on("--check")               { opts[:check] = true }
    o.on("--check-trackers")      { opts[:check_trackers] = true }
    o.on("--list")                { opts[:list] = true }
    o.on("--prune")               { opts[:prune] = true }
    o.on("--prune-days N", Integer, "Age threshold for --prune (default 30)") { |n| opts[:prune_days] = n }
    o.on("--yes", "Actually delete with --prune") { opts[:yes] = true }
    o.on("--source SRC", SOURCES, "Discovery: taste, seeded, all (default: #{DEFAULT_SOURCE})") { |s| opts[:source] = s }
    o.on("--stall-timeout SEC", Integer, "Kill aria2 after SEC without bytes (default #{DEFAULT_STALL})") { |n| opts[:stall] = n }
    o.on("-j", "--jobs N", Integer, "Download N titles at once (default #{DEFAULT_JOBS})") { |n| opts[:jobs] = n }
    o.on("--dead-after SEC", Integer, "Drop a stream with no data after SEC (default #{DEFAULT_DEAD})") { |n| opts[:dead] = n }
    o.on("--reset-skipped",       "Clear skipped entries for retry") { opts[:reset_skipped] = true }
    o.on("--reset-failed",        "Clear failed entries for retry")  { opts[:reset_failed] = true }
    o.on("--reset-all",           "Clear both skipped and failed")   { opts[:reset_all] = true }
    o.on("--verbose",             "Show backtraces and aria2 logs")  { opts[:verbose] = true }
    o.on("-h", "--help")          { puts o; exit 0 }
  end.parse!(argv)

  ENV["MOV_DEBUG"] = "1" if opts[:verbose]
  $stream_cache = {}

  %i[limit years stream_days jobs stall dead prune_days].each do |key|
    raise ArgumentError, "#{key} must be positive" if opts[key] && opts[key] <= 0
  end
  raise ArgumentError, "limit must be at most #{DISCOVER_PROBE}" if opts[:limit].to_i > DISCOVER_PROBE
  raise ArgumentError, "years must be at most 125" if opts[:years].to_i > 125
  $discover_years = opts[:years] || DISCOVER_YEARS
  $stream_days = opts[:stream_days] || STREAM_DAYS
  raise ArgumentError, "stream-days must be at most 180" if $stream_days > 180
  $include_bw = opts[:include_bw]
  $min_rating = opts.fetch(:min_rating, MIN_RT_RATING)
  raise ArgumentError, "min-rating must be between 0 and 100" unless $min_rating.between?(0, 100)
  $require_rating = opts[:require_rating]
  $rt_scores = {}
  $offline = opts[:offline]
  raise ArgumentError, "--offline requires --recommend" if $offline && !opts[:recommend]
  read_only = %i[status check check_trackers list prune reset_all reset_skipped reset_failed recommend dry_run].any? { |key| opts[key] }
  preflight!(download: !read_only)
  lock = File.open(File.join(CFG_DIR, "run.lock"), File::RDWR | File::CREAT, 0o600)
  unless lock.flock(File::LOCK_EX | File::LOCK_NB)
    say("mov0: another instance is active")
    return
  end
  state = State.new(STATE_PATH)
  cache = Cache.new(CACHE_DIR)

  return cmd_status(state, cache)   if opts[:status]
  return cmd_check(state, cache)    if opts[:check]
  return cmd_check_trackers(cache)  if opts[:check_trackers]
  return cmd_list(state)            if opts[:list]
  return cmd_prune(state, days: opts[:prune_days] || 30, yes: opts[:yes]) if opts[:prune]

  if opts[:reset_all]
    n = state.clear_status("skipped", "interrupted", "failed")
    say("db0: cleared #{n} entries")
    return
  end
  if opts[:reset_skipped]
    n = state.clear_status("skipped", "interrupted")
    say("db0: cleared #{n} skipped entries")
    return
  end
  if opts[:reset_failed]
    n = state.clear_status("failed")
    say("db0: cleared #{n} failed entries")
    return
  end

  if opts[:recommend]
    raise ArgumentError, "--recommend does not accept explicit titles" unless argv.empty?
    discover_by_taste(cache, state, want: opts[:limit] || TASTE_WANT, recommend: true)
    return
  end
  # Staging and log cleanup is explicit via --prune --yes.

  stats       = Hash.new(0)
  stall       = opts[:stall] || DEFAULT_STALL
  source      = opts[:source] || DEFAULT_SOURCE
  jobs        = opts[:jobs] || DEFAULT_JOBS
  $dead_after = opts[:dead] || DEFAULT_DEAD

  boot_banner(source, stall, jobs)

  dry   = opts[:dry_run]
  run_t = lambda do |t|
    { label: t.title, est_mb: t.est_mb.to_i,
      run: -> { t.movie? ? process_movie(t, state, cache, dry, stats, stall)
                         : process_series(t, state, cache, dry, stats, stall) } }
  end
  items = []

  if argv.any?
    say("mov0: explicit #{argv.join(' ')}")
    argv.each do |q|
      if (d = direct_item(q))
        items << { label: d[:title], est_mb: size_mib(d[:title]),
                   run: -> { process_seeded_one(d, state, cache, dry, stats, stall) } }
      elsif DIRECT_RE.match?(q)
        say("mov0: invalid direct input")
      else
        resolve_query(q).each { |t| items << run_t.(t) }
      end
    end
    if items.empty?
      say("mov0: no candidates")
      return
    end
  else
    taste_targets = []
    seeded        = []

    if %w[taste all].include?(source)
      taste_targets = discover_by_taste(cache, state, want: opts[:limit] || TASTE_WANT)
      say("taste0: #{taste_targets.size} candidates")
    end

    if %w[seeded all].include?(source) && !$exit_now
      say("apibay0: probing top recent")
      seeded = seeded_candidates(state, cache)
      say("apibay0: #{seeded.size} candidates")
    end

    if taste_targets.empty? && seeded.empty?
      say("mov0: no candidates")
      c = state.counts
      if c[:total].positive?
        say("mov0: hint: state has #{c[:total]} entries — try --reset-skipped / --reset-failed / --reset-all")
        say("mov0: hint: or --source seeded for real-seeded content")
      end
      return
    end

    items = taste_targets.map(&run_t) +
            seeded.map do |c|
              { label: c[:title], est_mb: c[:size_mib].to_i,
                run: -> { process_seeded_one(c, state, cache, dry, stats, stall) } }
            end
  end

  say("mov0: #{items.size} titles queued on #{dry ? 1 : jobs} aria")
  planned = items.sum { |it| it[:est_mb].to_i } / 1024.0 * 1.2
  if planned.positive?
    spare = free_gb - MIN_FREE_GB
    say("mov0: queue needs #{planned.round(1)}GB incl. headroom; #{spare.round(1)}GB unreserved")
  end
  run_pool(items, dry ? 1 : jobs)

  say("mov0: run complete")
  say("mov0:   would #{stats[:would]}") if opts[:dry_run] && stats[:would].positive?
  say("mov0:   downloaded #{stats[:downloaded]} (#{(state.counts[:bytes] / (1024.0**3)).round(1)}GB total)")
  say("mov0:   skipped already-tracked #{stats[:skipped]}") if stats[:skipped].positive?
  say("mov0:   skipped by user #{stats[:skipped_by_user]}") if stats[:skipped_by_user].positive?
  say("mov0:   skipped no-stream #{stats[:no_streams]}") if stats[:no_streams].positive?
  say("mov0:   failed #{stats[:failed]}") if stats[:failed].positive?
  say("mov0:   disk-full #{stats[:disk_full]}") if stats[:disk_full].positive?
  say("disk0: free #{free_gb.round(1)}GB")

  if !opts[:dry_run] && stats[:downloaded].zero? && stats[:failed].positive?
    exit 1
  end
rescue Interrupt
  say("mov0: interrupted")
  exit 130
rescue StandardError => e
  say("mov0: fatal: #{e.class}: #{e.message}")
  say(e.backtrace.first(5).map { |l| "mov0:   #{l}" }.join("\n")) if ENV["MOV_DEBUG"]
  exit 1
ensure
  lock&.close
end

if __FILE__ == $PROGRAM_NAME
  run(ARGV.dup)
end
