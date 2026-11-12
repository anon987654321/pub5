#!/usr/bin/env ruby
# frozen_string_literal: true

# dilla — the STUDIO beat engine.
#
# Pure-Ruby synthesis and dependency-free spectral reference analysis. The
# optional reference downloader uses the yt-dlp executable; no Python modules,
# NumPy, SciPy or Demucs runtime is required.
#
# Everything MASTER expects from `STUDIO/dilla/dilla.rb` is answered here:
#   ruby dilla.rb                       curated showcase (Blue Hour)
#   ruby dilla.rb --random --out X      random progression, random drums
#   ruby dilla.rb --showcase [--no-video] --out X
#   ruby dilla.rb --progression N [--drums ID] [--profile P] [--groove S]
#                      [--bpm X] [--kit K] [--voice V] [--rig R]
#                      [--sonitex P] [--sonitex-instances N] [--vcs X]
#                      [--drum-balance dB] [--chord-balance dB] [--bars N]
#                      [--seed N] [--out X]
#   ruby dilla.rb --list
#   ruby dilla.rb reference <url|file> [--style j_dilla] [--no-stems] [--max-duration S]
#   ruby dilla.rb industrial-techno --out X [--bpm X] [--bars N]
#   ruby dilla.rb output-path dilla-render-directory [ISO8601]
#   ruby dilla.rb output-path reference-root
#   ruby dilla.rb demo-each
#
# Sample flip (operator-supplied, rights-cleared audio only):
#   SAMPLE_LOOP=file SAMPLE_LOOP_VOL=0.42 SAMPLE_LOOP_WEIGHT=0.6 ruby dilla.rb …
#   … --sample-vol 0.42 --sample-weight 0.6 --sample-slices 8

require "json"
require "fileutils"
require "rbconfig"
require "digest"
require "time"
require "tmpdir"
require "tempfile"
require_relative "../subprocess"
require_relative "lib/reference_analyzer"

module Dilla
  ENGINE_ROOT = File.expand_path(__dir__)
  DATA_DIR = File.join(ENGINE_ROOT, "data")
  SCRIPT_PATH = File.expand_path(__FILE__)
  VERSION = "4.2.0"
  SAMPLE_RATE = 44_100

  module_function

  # ------------------------------------------------------------------ loading

  # Write beside the destination and rename only after the complete contents
  # have reached disk. A render may replace its previous take, but readers never
  # see a half-written WAV or sidecar when a process is interrupted.
  def atomic_write(path, contents, binary: false)
    destination = File.expand_path(path)
    directory = File.dirname(destination)
    existing = begin
      File.lstat(destination)
    rescue Errno::ENOENT
      nil
    end
    if existing && (!existing.file? || existing.symlink?)
      raise ArgumentError, "refusing to replace non-regular output: #{destination}"
    end

    mode = existing ? existing.mode & 0o777 : (0o666 & ~File.umask)
    Tempfile.create([".#{File.basename(destination)}.", ".tmp"], directory) do |file|
      file.binmode if binary
      file.write(contents)
      file.flush
      file.fsync
      file.chmod(mode)
      File.rename(file.path, destination)
    end
    path
  end

  def load_json(name)
    path = File.join(DATA_DIR, name)
    JSON.parse(File.read(path))
  rescue Errno::ENOENT, JSON::ParserError => e
    abort "dilla: cannot read #{path}: #{e.message}"
  end

  def catalogue
    @catalogue ||= load_json("dilla.json")
  end

  def theory
    @theory ||= load_json("music_theory.json")
  end

  def recovered
    @recovered ||= load_json("recovered_music.json")
  end

  def showcase_data
    @showcase_data ||= load_json("showcase.json")
  end

  # Artist-sourced recordings lead the menu. Engine studies, authored theory
  # progressions and lower-confidence recovered notes remain separate tiers.
  # Aliases are deliberately deduplicated in recovered_music.json.
  def progressions
    @progressions ||= begin
      verified = Array(recovered["artist_verified_progressions"]).map { |p| p.merge("source" => "artist_verified") }
      charts = Array(recovered["chart_references"]).map { |p| p.merge("source" => "chart_reference") }
      studies = Array(recovered["engine_modules"]).map { |p| p.merge("source" => "engine_study") }
      verified_ids = verified.map { |p| p["id"] }
      base = catalogue.fetch("progressions").map { |p| p.merge("source" => "engine") }
      rec = recovered.fetch("progressions").reject { |p| verified_ids.include?(p["id"]) }
                    .map { |p| p.merge("source" => "recovered") }
      verified.concat(charts).concat(studies).concat(base).concat(rec)
    end
  end

  def progression_by_ref(ref)
    list = progressions
    return list.fetch(Integer(ref) - 1) if ref.match?(/\A\d+\z/) && Integer(ref).between?(1, list.length)

    list.find { |p| p["id"] == ref } or abort "dilla: no progression named #{ref.inspect}"
  end

  # ------------------------------------------------------------------ CLI

  class Options
    attr_accessor :mode, :source, :out, :progression, :drums, :profile, :groove, :bpm,
                  :kit, :voice, :rig, :sonitex, :sonitex_instances, :vcs, :drum_balance,
                  :chord_balance, :bars, :seed, :performer, :style, :no_stems, :max_duration,
                  :video, :mp3, :midi, :midi_out, :foley, :sample_vol, :sample_weight,
                  :sample_slices, :sample_loop, :extra, :output_at

    def initialize
      @mode = :render
      @sonitex_instances = 1
      @video = false
      @mp3 = false
      @midi = false
      @foley = false
      @no_stems = false
      @style = "j_dilla"
      @extra = {}
    end
  end

  def parse_cli(argv)
    opts = Options.new
    args = argv.dup
    # Positional modes first: they read like commands, not flags.
    first = args.first
    case first
    when "reference"
      opts.mode = :reference
      args.shift
      opts.source = args.shift or abort "dilla reference: provide a YouTube URL or local audio file"
    when "industrial-techno"
      opts.mode = :industrial_techno
      args.shift
    when "output-path"
      opts.mode = :output_path
      args.shift
      opts.source = args.shift or abort "output-path: name dilla-render-directory or reference-root"
      # MASTER's contract appends the query time after the kind
      # (Contracts::Studio#query_output_path). Thread it into the path
      # authority, which scopes the default render root one folder per UTC
      # day -- the date the output-path contract test pins. The timestamp
      # stays optional: a bare query keeps the flat default directory.
      if args.first.to_s.match?(/\A\d{4}-\d{2}-\d{2}T/)
        opts.output_at = Time.iso8601(args.shift)
      end
    when "demo-each"
      opts.mode = :demo_each
      args.shift
    when "--help", "-h", nil
      opts.mode = (first == "--help" || first == "-h") ? :help : :showcase
      args.shift if first
    end

    until args.empty?
      flag = args.shift
      value_flag = ->(name) {
        v = args.shift
        abort "dilla: #{flag} needs a value" unless v
        opts.public_send("#{name}=", v)
      }
      case flag
      when "--out" then value_flag.call(:out)
      when "--progression" then value_flag.call(:progression)
      when "--drums" then value_flag.call(:drums)
      when "--profile" then value_flag.call(:profile)
      when "--groove" then value_flag.call(:groove)
      when "--bpm" then value_flag.call(:bpm)
      when "--bars" then value_flag.call(:bars)
      when "--kit" then value_flag.call(:kit)
      when "--voice" then value_flag.call(:voice)
      when "--rig", "--effect-rig" then value_flag.call(:rig)
      when "--sonitex" then value_flag.call(:sonitex)
      when "--sonitex-instances" then value_flag.call(:sonitex_instances)
      when "--vcs" then value_flag.call(:vcs)
      when "--drum-balance" then value_flag.call(:drum_balance)
      when "--chord-balance" then value_flag.call(:chord_balance)
      when "--seed" then value_flag.call(:seed)
      when "--performer" then value_flag.call(:performer)
      when "--style" then value_flag.call(:style)
      when "--max-duration" then value_flag.call(:max_duration)
      when "--sample-vol" then value_flag.call(:sample_vol)
      when "--sample-weight" then value_flag.call(:sample_weight)
      when "--sample-slices" then value_flag.call(:sample_slices)
      when "--sample-loop" then value_flag.call(:sample_loop)
      when "--no-stems" then opts.no_stems = true
      when "--video" then opts.video = true
      when "--no-video" then opts.video = false
      when "--mp3" then opts.mp3 = true
      when "--midi" then opts.midi = true
      when "--midi-out" then value_flag.call(:midi_out)
      when "--foley" then opts.foley = true
      when "--random" then opts.mode = :random
      when "--showcase" then opts.mode = :showcase
      when "--list" then opts.mode = :list
      else abort "dilla: unknown flag #{flag.inspect} (see --help)"
      end
    end
    opts
  end

  def help_text
    <<~TEXT
      dilla #{VERSION} - the STUDIO beat engine
      usage:
        ruby dilla.rb                            render the section-aware 24-bar showcase
        ruby dilla.rb --list                     progressions, drums, grooves and profiles
        ruby dilla.rb --style PROFILE             j_dilla/flying_lotus/jazz_soul/funk/
                                                 ambient/drum_and_bass/noise_sound_design/royksopp
        ruby dilla.rb --random --out PATH         random progression and drum grammar
        ruby dilla.rb --progression N|--id --out PATH
            [--drums ID] [--profile P] [--groove 0.85-1.25] [--bpm X] [--bars N]
            [--kit K] [--voice V] [--rig R] [--sonitex P] [--sonitex-instances N]
            [--vcs 0.0-1.0] [--drum-balance ±dB] [--chord-balance ±dB]
            [--seed N] [--performer ID] [--mp3] [--midi] [--midi-out PATH] [--foley]
        ruby dilla.rb reference URL|FILE [--style j_dilla|industrial_techno|general]
            [--no-stems] [--max-duration S]
            optional yt-dlp download + bounded Ruby spectral analysis of the mix;
            no Python, Demucs, NumPy, SciPy or native gem is required.
        ruby dilla.rb industrial-techno --out PATH [--bpm X] [--bars N]
        ruby dilla.rb output-path dilla-render-directory [ISO8601]
        ruby dilla.rb output-path reference-root
        ruby dilla.rb demo-each                  catalogue, one mp3 per track
      sample flip:
        SAMPLE_LOOP=rights-cleared.wav [--sample-vol 0.42] [--sample-weight 0.6] [--sample-slices 8]
    TEXT
  end

  def run(argv)
    opts = parse_cli(argv)
    case opts.mode
    when :help then puts help_text
    when :output_path then output_path(opts)
    when :list then print_list
    when :reference then reference(opts)
    when :industrial_techno then render_industrial_techno(opts)
    when :demo_each then demo_each
    when :random then render_random(opts)
    when :showcase then render_showcase(opts)
    else render(opts)
    end
  end

  def output_path(opts)
    require_relative File.join("..", "output_paths")
    case opts.source
    when "dilla-render-directory"
      puts Studio::OutputPaths.dilla_render_directory(at: opts.output_at)
    when "reference-root"
      puts Studio::OutputPaths.reference_root
    else
      abort "output-path: unknown kind #{opts.source.inspect}"
    end
  end

  def print_list
    puts "Progressions:"
    progressions.each_with_index do |p, i|
      source_tag = {
        "artist_verified" => "[record]",
        "chart_reference" => "[chart]",
        "engine_study" => "[study]",
        "engine" => "[original]",
        "recovered" => "[recovered]"
      }.fetch(p["source"], "")
      tempo = p["bpm"] ? "#{p['bpm']} BPM" : "tempo not pinned"
      puts format("  %2d  %-18s %-28s %s %s", i + 1, p["id"], p["title"].to_s[0, 28],
                  "#{p['key']} #{tempo}", source_tag)
    end
    puts "Drum patterns: #{catalogue.fetch('drum_patterns').keys.reject { |k| k == 'comment' }.join(', ')}"
    puts "Groove profiles: #{catalogue.fetch('groove_profiles').keys.reject { |k| k == 'comment' }.join(', ')}"
    puts "Kits: #{catalogue.fetch('kits').keys.reject { |k| k == 'comment' }.join(', ')}"
    puts "Voices: #{catalogue.fetch('voices').keys.join(', ')}"
    puts "Rigs: #{catalogue.fetch('rigs').keys.reject { |k| k == 'comment' }.join(', ')}"
    puts "Sonitex: #{catalogue.fetch('sonitex').keys.reject { |k| k == 'comment' }.join(', ')}"
    puts "Performers: #{catalogue.fetch('performers').map { |p| p['id'] }.join(', ')}"
  end

  def render_showcase(opts)
    show = showcase_data
    profile = catalogue.fetch("production_profiles", {}).fetch(opts.style.to_s, {})
    opts.progression ||= profile["progression"] || show.fetch("progression")
    opts.kit ||= profile["kit"] || show.fetch("kit")
    opts.voice ||= profile["voice"] || show.fetch("voice")
    opts.rig ||= profile["rig"] || show.fetch("rig")
    opts.sonitex ||= profile["sonitex"] || show.fetch("sonitex")
    opts.drums ||= profile["drums"]
    opts.sonitex_instances = show.fetch("sonitex_instances") unless opts.sonitex_instances && opts.sonitex_instances != 1
    opts.vcs ||= show.fetch("vcs").to_s
    opts.bpm ||= (profile["bpm"] || show.fetch("bpm")).to_s
    opts.foley = true if profile["foley"] && !opts.foley
    opts.bars ||= Array(show["arrangement"]).sum { |section| section.fetch("bars", 0).to_i } if opts.style.to_s == "j_dilla"
    render(opts, showcase: (opts.style.to_s == "j_dilla" ? show : show.merge("arrangement" => [])))
  end

  def render_random(opts)
    rnd = Random.new
    opts.progression = (1..progressions.length).to_a.sample(random: rnd).to_s
    opts.drums ||= catalogue.fetch("drum_patterns").keys.reject { |k| k == "comment" }.sample(random: rnd)
    render(opts)
  end

  def demo_each
    dest = render_destination_root
    manifest = []
    progressions.each_with_index do |p, i|
      opts = Options.new
      opts.progression = (i + 1).to_s
      opts.seed = Digest::SHA256.hexdigest("demo-each #{p['id']}")[0, 8].to_i(16).to_s
      name = format("%02d_%s", i + 1, p["id"])
      out = File.join(dest, "#{name}.mp3")
      opts.out = out
      opts.mp3 = true
      result = render(opts, quiet: true)
      manifest << [name, p["id"], result[:seed], result[:performer], p["bpm"], result[:bpm]].join("\t")
      puts "demo-each: #{out}"
    end
    Dilla.atomic_write(File.join(dest, "demo_manifest.tsv"), manifest.join("\n") << "\n")
    puts "demo-each: wrote #{progressions.length} renders and demo_manifest.tsv into #{dest}"
  end

  def render_destination_root
    env = ENV["DILLA_OUTPUT_DIR"].to_s.strip
    dir = if env.empty?
            require_relative File.join("..", "output_paths")
            Studio::OutputPaths.dilla_render_directory
          else
            File.expand_path(env)
          end
    FileUtils.mkdir_p(dir)
    dir
  end
end

module Dilla
  module_function

  # ------------------------------------------------------------- random source

  # One seeded stream for the whole render: a render is reproducible from its
  # seed, and the seed is recorded in the provenance sidecar.
  class Rng
    def initialize(seed)
      @rng = seed.nil? ? Random.new : Random.new(Integer(seed))
      @seed = seed.nil? ? @rng.rand(1..999_999_999) : Integer(seed)
    end

    attr_reader :seed

    def rand(range = nil)
      range ? @rng.rand(range) : @rng.rand
    end

    def pick(array)
      array.fetch(@rng.rand(array.length))
    end

    def chance(p) = @rng.rand < p

    # Gaussian-ish jitter in ms from a sigma.
    def jitter_ms(sigma)
      return 0.0 if sigma.to_f <= 0

      u1 = @rng.rand
      u2 = @rng.rand
      Math.sqrt(-2.0 * Math.log(u1 + 1e-12)) * Math.cos(2.0 * Math::PI * u2) * sigma
    end
  end

  # ------------------------------------------------------------- chord parsing

  NOTE_RE = /\A([A-G])([#b]?)(.*)\z/.freeze

  # Parses "Ab13", "Fm9", "Dbmaj9#11", "C7b9", "D7alt", "Gsus4", "C6/9",
  # "Dm7b5", "E7#9", "Bb/E" slash bass. Returns pitch-class intervals.
  module ChordParser
    module_function

    def parse(symbol, theory)
      m = NOTE_RE.match(symbol.strip) or raise ArgumentError, "cannot parse chord #{symbol.inspect}"
      root_name = m[1] + m[2]
      rest = m[3]
      quality, modifiers, bass = split_quality(rest)
      table = theory.fetch("qualities")
      intervals = table.fetch(quality) { table.fetch("7") }
      intervals = apply_modifiers(intervals, modifiers)
      root_pc = theory.fetch("keys").fetch(root_name) { raise ArgumentError, "unknown root #{root_name}" }
      bass_pc = bass && theory.fetch("keys")[bass]
      named_voicing = theory.fetch("named_voicings", {}).fetch(symbol, nil)
      {
        root: root_pc, intervals: intervals.uniq.sort, quality: quality,
        bass: bass_pc, symbol: symbol, voicing_midi: named_voicing
      }
    end

    def split_quality(rest)
      bass = nil
      if (i = rest.rindex("/"))
        candidate = rest[(i + 1)..]
        if candidate.match?(/\A[A-G][#b]?\z/)
          bass = candidate
          rest = rest[0...i]
        end
      end

      # These spellings belong to the historical record charts. Keep their
      # labels on the chord event, while resolving them to usable harmony.
      aliases = {
        "m7fil" => ["m9", []],
        "7climax" => ["9", []],
        "m11nc" => ["m11", []],
        "7nc" => ["7", []],
        "maj9nc" => ["maj9", []],
        "Maj13s11" => ["maj13", ["#11"]],
        "Maj7overG" => ["maj7", []]
      }
      if aliases.key?(rest)
        quality, legacy_modifiers = aliases.fetch(rest)
        bass ||= "G" if rest == "Maj7overG"
        return [quality, legacy_modifiers, bass]
      end
      return ["7alt", [], bass] if rest == "7alt"

      modifiers = []
      rest = rest.sub(/(b5|#5|b9|#9|#11|b13)\z/) { modifiers << Regexp.last_match(1); "" }
      quality = case rest
                when "", "maj", "M" then "maj"
                when "m", "min", "-" then "m"
                when "mMaj", "mM" then "mMaj7"
                when "mMaj7", "mM9" then rest == "mM9" ? "mMaj9" : "mMaj7"
                when "mMaj9", "mmaj9" then "mMaj9"
                else rest
                end
      [quality, modifiers, bass]
    end

    def apply_modifiers(intervals, modifiers)
      additions = { "b5" => 6, "#5" => 8, "b9" => 13, "#9" => 15, "#11" => 18, "b13" => 20 }
      replacements = { "b5" => 7, "#5" => 7, "b9" => 14, "#9" => 14, "#11" => 17, "b13" => 21 }
      modifiers.each do |mod|
        natural = replacements.fetch(mod)
        intervals = intervals.reject { |value| value % 12 == natural % 12 }
        intervals |= [additions.fetch(mod)]
      end
      intervals.compact.uniq.sort
    end
  end

  # ------------------------------------------------------------- voicing

  # Turns chord pitch classes into playable MIDI voicings. The bass owns
  # the root; the keys own the colour — the Rhodes practice behind the
  # recovered Slum Village transcriptions. Each chord sets three or four
  # tones: the shell defines the function, the extension defines the
  # colour, the 5th fills only what remains. Candidate stacks are scored
  # on total voice-leading motion from the previous chord, compact spread
  # and a top voice left in singing range.
  class Voicer
    TOP_RANGE = (67..84).freeze
    INNER_RANGE = (48..72).freeze
    LOWEST_VOICE = 48
    HIGHEST_VOICE = 92
    # A voice may not travel further than a perfect fifth between chords.
    # This is a constraint, not a preference: no amount of top-register
    # brightness or compactness buys back a leap that size.
    MAX_LEAD = 7

    def initialize(theory)
      @theory = theory
    end

    # chords: array of parsed chords; returns array of [midi notes]
    def voice(chords, rng, opts = {})
      out = []
      previous = nil
      chords.each do |chord|
        voiced = voice_one(chord, previous)
        out << voiced
        previous = voiced
      end
      out
    end

    def voice_one(chord, previous)
      if chord[:voicing_midi].is_a?(Array)
        named = named_voicing(chord[:voicing_midi], previous)
        return named if named
      end
      quartal = quartal_stack(chord)
      return quartal if quartal && within_lead?(quartal, previous)

      tone_sets = [chord_tones(chord), chord_tones(chord)[0...-1]].reject { |set| set.length < 3 }
      candidates = tone_sets.flat_map { |tone_set| candidate_stacks(tone_set) }
      # Two constraints are structural rather than preferential: the top voice
      # stays in singing register and no voice leaps more than a fifth. They
      # filter the pool before scoring, and relax one at a time only when a
      # tone set admits nothing — a leap is the worse of the two failures.
      pool = candidates.select { |stack| singing_top?(stack) && within_lead?(stack, previous) }
      pool = candidates.select { |stack| within_lead?(stack, previous) } if pool.empty?
      pool = candidates.select { |stack| singing_top?(stack) } if pool.empty?
      pool = candidates if pool.empty?
      pool.min_by { |stack| [score(stack, previous), stack.last - stack.first] } ||
        [chord[:root] + 60]
    end

    private

    # Source-specific grips are exact pitch lists recovered with the historical
    # transcriptions. Octave placement may move, but the internal grip does not.
    def named_voicing(notes, previous)
      base = notes.map(&:to_i).sort
      return if base.length < 3

      candidates = (-2..3).map { |octaves| base.map { |note| note + octaves * 12 } }
                          .select { |stack| stack.all? { |note| note.between?(24, 108) } && singing_top?(stack) }
      return if candidates.empty?

      pool = candidates.select { |stack| within_lead?(stack, previous) }
      pool = candidates if pool.empty?
      pool.min_by { |stack| [score(stack, previous), stack.last - stack.first] }
    end

    # A minor-eleventh shell can float in fourths from the fifth:
    # Cm11 = G-C-F-Bb-Eb. Use it only when every pitch is in the parsed chord.
    def quartal_stack(chord)
      return unless chord[:quality] == "m11"

      pitch_classes = chord[:intervals].map { |interval| interval % 12 }
      return unless [0, 3, 5, 7, 10].all? { |pitch_class| pitch_classes.include?(pitch_class) }

      start_pc = (chord[:root] + 7) % 12
      start = LOWEST_VOICE + ((start_pc - (LOWEST_VOICE % 12)) % 12)
      stack = Array.new(5) { |index| start + index * 5 }
      singing_top?(stack) ? stack : nil
    end

    # 3rd and 7th define the function; one extension defines the colour
    # (9th, #11th, 6th or the altered tension); the 5th fills only what
    # remains. The root is never stacked while a bass lane carries it.
    # Intervals are root-relative; each tone returns as an absolute pitch
    # class.
    def chord_tones(chord)
      root_pc = chord[:root] % 12
      rel = chord[:intervals].reject { |iv| iv % 12 == 0 }
      shell = [rel.find { |s| [3, 4].include?(s % 12) },
               rel.find { |s| [10, 11].include?(s % 12) }].compact
      colours = [1, 2, 5, 6, 9].map { |c| rel.find { |s| s % 12 == c } }
                                .compact.first(2)
      picks = shell + colours
      fifth = rel.find { |s| s % 12 == 7 }
      picks << fifth if picks.length < 4 && fifth
      picks << 0 if picks.length < 3
      picks.first(4).uniq.map { |iv| (root_pc + iv) % 12 }
    end

    # Every ascending arrangement of the pitch classes that fits the register
    # window, lowest voice first. The old generator produced a single shape
    # per tone set — root position pushed up into the top octave — which left
    # the compactor with nothing to choose from and forced leaps it then had
    # to accept.
    def candidate_stacks(tone_set, lowest = LOWEST_VOICE, highest = HIGHEST_VOICE)
      build = lambda do |stack, remaining|
        if remaining.empty?
          [stack]
        else
          remaining.flat_map.with_index do |pitch_class, index|
            note = pitch_class % 12
            note += 12 while note < (stack.empty? ? lowest : stack.last + 1)
            next [] if note > highest

            build.call(stack + [note], remaining[0...index] + remaining[index + 1..])
          end
        end
      end
      build.call([], tone_set)
    end

    def within_lead?(stack, previous)
      return true unless previous

      stack.all? { |note| previous.map { |p| (p - note).abs }.min <= MAX_LEAD }
    end

    def singing_top?(stack)
      stack.last.between?(TOP_RANGE.begin, TOP_RANGE.end)
    end

    def score(stack, previous)
      s = 0.0
      if previous
        common = [stack.length, previous.length].min
        s += (0...common).sum { |i| (stack[i] - previous[i]).abs * 10.0 }
        # Set-level smoothness too, however the stack reorders itself between
        # indices. Leadable candidates already satisfy this; it only shapes
        # the fallback used when a tone set admits no leadable stack.
        stack.each do |note|
          gap = previous.map { |p| (p - note).abs }.min
          s += (gap - MAX_LEAD) * 12.0 if gap > MAX_LEAD
        end
      end
      spread = stack.last - stack.first
      s += (spread - 22) * 0.4 if spread > 22
      s += (12 - spread) * 0.3 if spread < 12
      s += 8 unless singing_top?(stack)
      s += 6 if stack.first < 52
      s
    end
  end

  # Scale tones for melody over a chord.
  def scale_for(chord, theory)
    scale_name = theory.fetch("scale_for_chord").fetch(chord[:quality], "dorian")
    theory.fetch("scales").fetch(scale_name)
  end
end

module Dilla
  # ------------------------------------------------------------- sequencing

  # One musical event. time is seconds from render start (already includes all
  # groove math); the renderer turns lanes into samples.
  Event = Struct.new(:time, :dur, :lane, :midi, :vel, :meta)

  class Groove
    PPQN = 96

    def initialize(bpm:, swing:, profile:, performer:)
      @bpm = bpm.to_f
      @swing = swing.to_f.clamp(50.0, 66.0)
      @profile = profile
      @performer = performer
    end

    attr_reader :bpm

    def beat_s = 60.0 / @bpm
    def bar_s = beat_s * 4.0
    def sixteenth_s = bar_s / 16.0
    def eighth_s = bar_s / 8.0

    # MPC swing: the off-16th slides from the middle (50%) toward the triplet
    # (66%). Swing percent *is* the off-16th's position within the eighth, so
    # the slide spans the clamp (50..66) across that range: 54 lands in the
    # documented pocket, 66 lands exactly on the triplet.
    def swing_delay_s(lane = nil)
      lane_swing = lane && @profile.fetch("swing_by_lane", {}).fetch(lane.to_s, @swing)
      amount = (lane_swing || @swing).to_f.clamp(50.0, 66.0)
      position = 0.5 + ((amount - 50.0) / 16.0) * (2.0 / 3.0 - 0.5)
      (position - 0.5) * eighth_s
    end

    def step_offset_ms(lane, step)
      map = @profile.fetch("step_offsets_ms", {}).fetch(lane.to_s, {})
      (map[step.to_s] || (step.odd? ? map["odd"] : nil) || 0.0).to_f
    end

    def nudge(lane)
      nudge = @profile.fetch("nudge", {})
      base = { "kick" => 16.0, "snare" => -11.0, "hat" => -5.0, "ghost" => 8.0 }.fetch(lane, 0.0)
      (nudge.fetch(lane, base).to_f * (1.0 + @performer.fetch("kick_bias", 0.0)))
    end

    # The clap leads the backbeat, setting an early reference point for the ear.
    def clap_early_ms
      nudges = @profile.fetch("nudge", {})
      nudges.fetch("soulclap", nudges.fetch("snare", -11.0).to_f - 8.0).to_f
    end

    def spread(lane)
      @profile.fetch("spread_ms", 8.0) * (lane == "kick" ? 1.35 : 1.0)
    end

    def drag_s = @profile.fetch("drag_ms", 0.0) / 1000.0

    def anticipation_s
      @profile.fetch("anticipation", 0.0).to_f / 1000.0
    end
  end

  class Sequencer
    def initialize(progress:, groove:, drums:, rig:, rng:, performer:, opts: {})
      @progress = progress
      @groove = groove
      @drums = drums
      @rig = rig
      @rng = rng
      @performer = performer
      @opts = opts
    end

    # A section map can change harmony, drum grammar, active lanes and patch
    # identity without restarting the shared musical clock.
    def events
      arrangement = Array(@opts[:arrangement])
      return arranged_events(arrangement) unless arrangement.empty?
      flat_events(@opts.fetch(:bars))
    end

    private

    def flat_events(bar_count)
      loop_bars = [@progress["loop_bars"].to_i.clamp(1, 8), bar_count].min
      chord_plan = build_chord_plan(loop_bars, bar_count)
      drum_events = build_drums(bar_count, loop_bars)
      melodic = build_melodic(chord_plan, loop_bars, bar_count)
      foley = @opts[:foley] ? build_foley(chord_plan) : []
      { drum: drum_events }.merge(melodic).merge(foley: foley)
    end

    def arranged_events(sections)
      output = { drum: [], chord: [], bass: [], melody: [], foley: [] }
      cursor_bars = 0
      sections.each do |section|
        bars = section.fetch("bars", 0).to_i
        next unless bars.positive?
        progression = Dilla.progression_by_ref(section["progression"] || @progress.fetch("id"))
        drum_id = section["drums"]
        drums = drum_id ? Dilla.catalogue.fetch("drum_patterns").fetch(drum_id) : @drums
        active = Array(section["layers"]).map(&:to_s)
        active = %w[drums chords bass melody foley] if active.empty?
        child = self.class.new(
          progress: progression, groove: @groove, drums: drums, rig: @rig,
          rng: @rng, performer: @performer,
          opts: { bars: bars, foley: active.include?("foley") }
        )
        rendered = child.events
        lane_names = { drum: "drums", chord: "chords", bass: "bass", melody: "melody", foley: "foley" }
        rendered.each do |lane, lane_events|
          next unless active.include?(lane_names.fetch(lane))
          lane_events.each do |event|
            local_time = event.time
            event.time += cursor_bars * @groove.bar_s
            if %i[chord melody].include?(lane)
              meta = event.meta.is_a?(Hash) ? event.meta.dup : {}
              meta["section"] = section["section"]
              meta["voice"] = section["voice"] if section["voice"]
              if section["morph_to"]
                progress = (local_time / [bars * @groove.bar_s, 0.001].max).clamp(0.0, 1.0)
                meta["morph_to"] = section["morph_to"]
                meta["morph_mix"] = section.fetch("morph_start", 0.0).to_f +
                                    (section.fetch("morph_end", 1.0).to_f - section.fetch("morph_start", 0.0).to_f) * progress
              end
              event.meta = meta
            end
            output.fetch(lane) << event
          end
        end
        cursor_bars += bars
      end
      output
    end

    private

    def step_time(bar, step, lane = nil)
      t = bar * @groove.bar_s + step * @groove.sixteenth_s
      t += @groove.swing_delay_s(lane) if step.to_f == step.to_i && step.to_i.odd?
      t
    end

    def drum_hit(bar, step, lane, vel)
      groove_lane = lane == "ghost" ? "ghost" : (lane == "hats" || lane == "open_hat" ? "hat" : lane)
      jitter = @groove.spread(groove_lane)
      @timing_offsets ||= {}
      offset = @timing_offsets.fetch([groove_lane, step]) do
        @timing_offsets[[groove_lane, step]] = @rng.jitter_ms(jitter) / 1000.0
      end
      nudge_ms = groove_lane == "soulclap" ? @groove.clap_early_ms : @groove.nudge(groove_lane)
      t = step_time(bar, step, groove_lane) + (nudge_ms / 1000.0) +
          (@groove.step_offset_ms(groove_lane, step) / 1000.0) + offset
      vel = (vel * (1.0 + @rng.jitter_ms(2.8) / 100.0)).clamp(0.05, 1.0)
      Event.new(t + @groove.drag_s, 0.0, lane.to_sym, nil, vel, nil)
    end

    def build_drums(bar_count, loop_bars)
      events = []
      bust_bars = @drums.fetch("bust_bars", 4)
      fills = catalogue_fetch_busts
      hat_level_bias = @performer.fetch("hat_level", 0.0)
      ghost_bias = @performer.fetch("ghost_bias", 0.0)
      bar_count.times do |bar|
        is_bust = ((bar + 1) % bust_bars).zero? && bar != bar_count - 1 && bar > 1
        DRUM_LANES.each do |lane|
          steps = @drums.fetch(lane, [])
          steps.each do |entry|
            step, vel = entry
            next if is_bust && %w[kick snare].include?(lane) && lane == "kick" && step >= 8

            vel = vel * (1.0 + hat_level_bias) if lane == "hats"
            vel = (vel * (1.0 + ghost_bias)).clamp(0.05, 1.0) if lane == "ghost"
            events << drum_hit(bar, step, lane, vel)
          end
        end
        if is_bust
          fill = fills.fetch(@rng.rand(fills.length))
          fill.each do |lane, steps|
            steps.each { |entry| events << drum_hit(bar, entry[0], lane, entry[1]) }
          end
        end
      end
      events.sort_by!(&:time)
      events
    end

    def catalogue_fetch_busts
      Dilla.catalogue.fetch("busts").fetch("fill_patterns")
    end

    def build_chord_plan(loop_bars, bar_count)
      chords = @progress["chords"]
      per_chord = @progress["bars_per_chord"]
      plan = []
      chord_bars = Array(@progress["chord_bars"]).map(&:to_f)
      if chord_bars.length == chords.length && chord_bars.all? { |bars| bars.finite? && bars.positive? }
        idx = 0
        pos = 0.0
        while pos < bar_count
          span = [chord_bars[idx % chord_bars.length], bar_count - pos].min
          plan << { index: idx % chords.length, start_bar: pos, bars: span }
          idx += 1
          pos += span
        end
      elsif per_chord && per_chord < 1
        step_bars = 1.0 / per_chord.to_f
        idx = 0
        pos = 0.0
        while pos < bar_count
          span = [step_bars, bar_count - pos].min
          plan << { index: idx % chords.length, start_bar: pos, bars: span }
          idx += 1
          pos += span
        end
      else
        bpc = (per_chord || 1).to_f
        idx = 0
        pos = 0.0
        while pos < bar_count
          span = [bpc, bar_count - pos].min
          plan << { index: idx % chords.length, start_bar: pos, bars: span }
          idx += 1
          pos += span
        end
      end
      plan
    end

    # Harmony rides the MPC grid itself; only the drum kit carries lane
    # nudges and loop drag. The reference corpus measures chords ~18 ms
    # ahead of the kick-anchored grid — exactly where the straight grid
    # sits once the kick is nudged late.
    def build_melodic(plan, loop_bars, bar_count)
      voicer = Voicer.new(Dilla.theory)
      parsed = @progress["chords"].map { |sym| Dilla::ChordParser.parse(sym, Dilla.theory) }
      voiced = voicer.voice(parsed, @rng)
      feel = @progress["feel"] || {}
      out = { chord: [], bass: [], melody: [] }

      plan.each do |slot|
        chord = parsed.fetch(slot[:index])
        voicing = voiced.fetch(slot[:index])
        start = slot[:start_bar] * @groove.bar_s
        dur = slot[:bars] * @groove.bar_s * 0.98
        vel = 0.6 + @rng.jitter_ms(3.0) / 100.0
        out[:chord] << Event.new(start, dur, :chord, voicing, vel, { symbol: chord[:symbol] })
        # Mid-slot Rhodes bounce: the second, softer rearticulation that
        # carries the Dilla comping feel. Skipped sometimes so it breathes.
        if slot[:bars] >= 0.9 && @rng.chance(0.65)
          stab_at = slot[:start_bar] * @groove.bar_s + @groove.beat_s * 2.5
          if stab_at < (slot[:start_bar] + slot[:bars]) * @groove.bar_s
            out[:chord] << Event.new(stab_at, dur * 0.42, :chord, voicing,
                                     (vel * 0.58).clamp(0.1, 1.0), { symbol: chord[:symbol] })
          end
        end
        out[:bass].concat(bass_events(chord, slot, parsed, plan))
        out[:melody].concat(melody_events(chord, slot, plan))
      end
      out
    end

    def bass_events(chord, slot, parsed, plan)
      style = (@progress["feel"] || {}).fetch("bass", "dub")
      start_bar = slot[:start_bar]
      span_s = slot[:bars] * @groove.bar_s
      root_midi = 24 + chord[:root] # low register
      root_midi += 12 while root_midi < 33
      events = []
      case style
      when "dub"
        t = start_bar * @groove.bar_s
        # Three hits, not two: the off-beat "and" at a third of the span is
        # the dub bounce the reference bass stems carry (~5.5 onsets/bar).
        events << Event.new(t, span_s * 0.30, :bass, root_midi, 0.85, nil)
        events << Event.new(t + span_s * 0.33, span_s * 0.24, :bass, root_midi, 0.62, nil)
        events << Event.new(t + span_s * 0.66, span_s * 0.3, :bass, root_midi, 0.7, nil)
        events << Event.new(t, span_s * 0.62, :bass, root_midi + 12, 0.3, nil) if @rng.chance(0.25)
      when "walk"
        beats = (slot[:bars] * 4).ceil
        next_chord = parsed.fetch((slot[:index] + 1) % parsed.length) { chord }
        beats.times do |b|
          t = start_bar * @groove.bar_s + b * @groove.beat_s
          midi = if b.zero?
                   root_midi
                 elsif b == beats - 1
                   approach(next_chord[:root])
                 else
                   [root_midi, root_midi + 7, root_midi + 5].fetch(@rng.rand(3))
                 end
          events << Event.new(t, @groove.beat_s * 0.9, :bass, midi, 0.8, nil)
        end
      when "pedal"
        events << Event.new(start_bar * @groove.bar_s, span_s, :bass, 28, 0.75, nil)
        events << Event.new(start_bar * @groove.bar_s, span_s, :bass, 40, 0.4, nil)
      when "thumb"
        steps = { 0 => 0.9, 6 => 0.75, 10 => 0.85, 13 => 0.6 }
        bars = slot[:bars].ceil
        bars.times do |b|
          steps.each do |step, vel|
            t = step_time(slot[:start_bar] + b, step)
            next unless t >= slot[:start_bar] * @groove.bar_s

            midi = step.zero? ? root_midi : [root_midi, root_midi + 12, root_midi + 7].fetch(@rng.rand(3))
            events << Event.new(t, @groove.sixteenth_s * 2.2, :bass, midi, vel * 0.85, nil)
          end
        end
      end
      events
    end

    def approach(root_pc)
      target = 33 + root_pc
      target += 12 while target < 36
      target - 1
    end

    MELODY_RHYTHMS = {
      "dorian_moan" => [[0, 1.5], [1.5, 0.5], [2, 1.0], [4, 2.0], [7, 1.0]],
      "sweet_soul" => [[0, 1.0], [1, 0.5], [2, 1.5], [4, 1.0], [6, 2.0]],
      "music_box" => [[0, 0.5], [0.5, 0.5], [2, 1.0], [6, 0.5], [7, 1.0]],
      "horn_stabs" => [[1, 0.5], [3, 0.5], [5, 0.5], [7, 0.5], [9, 0.5]]
    }.freeze

    # Motif repeats per loop with identical deviations: generate once per loop
    # slot and copy. Blue notes land on weak beats; strong beats hold chord
    # tones; phrases end resolving to the root or fifth.
    def melody_events(chord, slot, plan)
      style = (@progress["feel"] || {}).fetch("melody", "dorian_moan")
      motif = Array(@progress["melody_midi"]).filter_map do |note|
        value = Integer(note) rescue nil
        value if value && value.between?(48, 84)
      end
      return [] if motif.empty? && @rng.chance(0.22)

      scale = Dilla.scale_for(chord, Dilla.theory)
      root_pc = chord[:root]
      rhythm = MELODY_RHYTHMS.fetch(style)
      events = []
      base = slot[:start_bar] * @groove.bar_s
      span = slot[:bars] * @groove.bar_s
      last_midi = @last_melody_midi
      motif_index = (slot[:start_bar].to_f * rhythm.length).round
      slot[:bars].ceil.times do |bar_offset|
        rhythm.each do |step, length|
          bar = slot[:start_bar] + bar_offset
          t = step_time(bar, step.to_f, "melody")
          next unless t < base + span
          next if motif.empty? && step.to_f.positive? && @rng.chance(0.08)

          strong = (step.to_f % 4).zero?
          midi = if motif.empty?
                   pick_melody_note(chord, scale, root_pc, strong, style, last_midi)
                 else
                   note = motif[motif_index % motif.length]
                   motif_index += 1
                   note
                 end
          last_midi = midi
          dur = length * @groove.sixteenth_s * 0.92
          events << Event.new(t, dur, :melody, midi, 0.62 + @rng.jitter_ms(5.0) / 100.0, nil)
          events << Event.new(t, dur, :melody, midi + 12, 0.3, nil) if style == "horn_stabs" && strong
        end
      end
      @last_melody_midi = last_midi
      events
    end

    def pick_melody_note(chord, scale, root_pc, strong, _style, previous = nil)
      chord_tones = chord[:intervals].map { |interval| (root_pc + interval) % 12 }.uniq
      scale_tones = scale.map { |degree| (root_pc + degree) % 12 }.uniq
      pitch_classes = (strong || @rng.chance(0.35)) ? chord_tones : scale_tones
      candidates = (72..83).select { |midi| pitch_classes.include?(midi % 12) }

      # Move by step when the scale offers a nearby choice; never invent a
      # passing note outside the chord or scale just to smooth the line.
      if previous && @rng.chance(strong ? 0.10 : 0.35)
        nearby = candidates.select { |midi| midi != previous && (midi - previous).abs <= 2 }
        return @rng.pick(nearby) unless nearby.empty?
      end
      @rng.pick(candidates)
    end

    # Scale-locked upper-register FM droplets and broken arpeggio fragments.
    def build_foley(chord_plan)
      parsed = @progress["chords"].map { |symbol| Dilla::ChordParser.parse(symbol, Dilla.theory) }
      # Seven droplet slots per bar: the reference corpus measures ~9 visible
      # harmonic onsets per bar; four slots left the arrangement bare.
      positions = [[1, 0.24], [3, 0.16], [5, 0.18], [7, 0.12], [10, 0.30], [12, 0.20], [14, 0.16]]
      events = []
      chord_plan.each do |slot|
        chord = parsed.fetch(slot[:index])
        scale = Dilla.scale_for(chord, Dilla.theory)
        chord_pcs = chord[:intervals].map { |iv| (chord[:root] + iv) % 12 }
        slot[:bars].ceil.times do |bar_index|
          positions.each_with_index do |(step, level), index|
            next if index == 1 && @rng.chance(0.22)
            next if index == 3 && @rng.chance(0.3)
            next if index == 5 && @rng.chance(0.2)
            next if index == 6 && @rng.chance(0.25)
            pool = index.even? ? chord_pcs : scale.map { |degree| (chord[:root] + degree) % 12 }
            midi = 84 + pool.fetch(@rng.rand(pool.length))
            at = (slot[:start_bar] + bar_index) * @groove.bar_s + step * @groove.sixteenth_s
            at += @groove.swing_delay_s("hat") if step.odd?
            next if at >= (slot[:start_bar] + slot[:bars]) * @groove.bar_s
            events << Event.new(at, 0.06 + @rng.rand * 0.13, :foley, midi, level * (0.75 + @rng.rand * 0.45), { "synth" => "fm_glass" })
          end
        end
      end
      events
    end
  end

  DRUM_LANES = %w[kick snare ghost hats ride perc open_hat soulclap].freeze
end

module Dilla
  # ------------------------------------------------------------- audio core

  # 65536-entry sine table with linear interpolation: notes render through
  # table lookup, which keeps a full stereo mixdown inside Ruby's comfort.
  SINE = Array.new(65_536) { |i| Math.sin(2.0 * Math::PI * i / 65_536) }.freeze

  def self.sine(phase)
    pos = phase.to_i & 65_535
    f = pos.floor
    frac = pos - f
    a = SINE[f]
    b = SINE[(f + 1) & 65_535]
    a + (b - a) * frac
  end

  # Shared noise stream buffer: one deterministic stream, random entry points.
  # Fixed-seed noise stream: every process sees the same noise, so a seeded
  # render reproduces exactly across runs. One Random, sequential draws —
  # Random.new(seed).rand *per sample* answered the same first float 262,144
  # times, a constant array that read as silence and cost 8s of boot.
  noise_stream = Random.new(0xD11A)
  NOISE = Array.new(262_144) { noise_stream.rand * 2.0 - 1.0 }.freeze

  class Stereo
    attr_accessor :l, :r

    def initialize(n)
      @l = Array.new(n, 0.0)
      @r = Array.new(n, 0.0)
    end

    def add_mono!(start, samples, level_l, level_r)
      n = @l.length
      i = 0
      lim = samples.length
      while i < lim
        idx = start + i
        if idx >= 0 && idx < n
          v = samples[i]
          @l[idx] += v * level_l
          @r[idx] += v * level_r
        end
        i += 1
      end
    end
  end

  module_function

  # Exponential-decay tone with attack; partials as [freq_ratio, amp, decay_scale].
  def render_tone(len, freq, vel, env: { attack: 0.008, decay: 1.2, sustain: 0.0 }, partials: [], lp: nil)
    out = Array.new(len, 0.0)
    attack = [(env[:attack] * SAMPLE_RATE).to_i, 1].max
    decay_coef = Math.exp(-1.0 / (env[:decay] * SAMPLE_RATE))
    sustain = env[:sustain]
    phase = 0.0
    lp_state = nil
    lp_coef = lp ? Math.exp(-2.0 * Math::PI * lp / SAMPLE_RATE) : nil
    inc = freq.to_f * 65_536 / SAMPLE_RATE
    i = 0
    while i < len
      env_val = if i < attack
                  i.to_f / attack
                else
                  sustain + (1.0 - sustain) * (decay_coef**(i - attack))
                end
      s = 0.0
      partials.each do |ratio, amp, dscale|
        pinc = inc * ratio
        pphase = (phase * ratio) % 65_536
        s += Dilla.sine(pphase.round) * amp * (decay_coef**((i - attack) * dscale))
      end
      s *= env_val * vel
      if lp_coef
        lp_state = lp_state.nil? ? s : lp_state + (s - lp_state) * (1.0 - lp_coef)
        s = lp_state
      end
      out[i] = s
      phase += inc
      i += 1
    end
    out
  end

  # ------------------------------------------------------------- instruments

  class Instruments
    def initialize(kit, voice, theory)
      @kit = kit
      @voice = voice
      @theory = theory
    end

    # Rhodes-style FM electric piano: sine carrier, tine partial at 4x that
    # dies fast, modulated brightness by velocity, optional tremolo.
    def rhodes(midi, vel, dur_s)
      f = midi_hz(midi)
      bright = @voice["brightness"].to_f
      len = (dur_s * SAMPLE_RATE).to_i + 1
      decay = @voice["decay"].to_f
      tine_amp = 0.22 * bright
      body_amp = 0.9 * vel
      trem = @voice["tremolo"].to_f
      trem_samples = (4.6 * SAMPLE_RATE).to_i
      out = Dilla.render_tone(
        len, f, body_amp,
        env: { attack: 0.006, decay: decay, sustain: 0.12 },
        partials: [[1.0, 1.0, 1.0], [2.0, 0.18 + 0.3 * bright, 0.6], [4.0, tine_amp, 0.12], [6.97, 0.05 * bright, 0.1]],
        lp: 2600 + 5200 * bright * vel
      )
      if trem.positive?
        i = 0
        depth = 0.5 * trem
        while i < len
          lfo = 1.0 - depth + depth * (1.0 + Math.sin(2.0 * Math::PI * i / trem_samples)) * 0.5
          out[i] *= lfo
          i += 1
        end
      end
      soft_clip(out)
    end

    def pad(midi, vel, dur_s)
      f = midi_hz(midi)
      len = (dur_s * SAMPLE_RATE).to_i + 1
      partials = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0].map.with_index { |h, idx| [h, (0.9**idx) * 0.5, 1.0] }
      out = Dilla.render_tone(
        len, f, 0.5 * vel,
        env: { attack: @voice["attack"].to_f, decay: @voice["decay"].to_f, sustain: 0.55 },
        partials: partials,
        lp: 1400 + 2600 * @voice["brightness"].to_f
      )
      # Two-voice detune chorus inside the pad: cheap width without haas smear.
      out2 = Dilla.render_tone(
        len, f * 1.003, 0.5 * vel,
        env: { attack: @voice["attack"].to_f * 1.4, decay: @voice["decay"].to_f, sustain: 0.55 },
        partials: partials,
        lp: 1200 + 2400 * @voice["brightness"].to_f
      )
      i = 0
      while i < len
        out[i] = 0.6 * out[i] + 0.4 * out2[i]
        i += 1
      end
      soft_clip(out)
    end

    def musicbox(midi, vel, dur_s)
      f = midi_hz(midi)
      len = (dur_s * SAMPLE_RATE).to_i + 1
      out = Dilla.render_tone(
        len, f, 0.8 * vel,
        env: { attack: 0.002, decay: @voice["decay"].to_f, sustain: 0.0 },
        partials: [[1.0, 1.0, 1.0], [3.01, 0.4, 0.35], [5.4, 0.12, 0.15]],
        lp: 6500
      )
      soft_clip(out)
    end

    def organ(midi, vel, dur_s)
      f = midi_hz(midi)
      len = (dur_s * SAMPLE_RATE).to_i + 1
      out = Dilla.render_tone(
        len, f, 0.6 * vel,
        env: { attack: 0.01, decay: @voice["decay"].to_f, sustain: 0.8 },
        partials: [[0.5, 0.35, 1.0], [1.0, 1.0, 1.0], [2.0, 0.5, 1.0], [3.0, 0.25, 1.0], [4.0, 0.2, 1.0], [8.0, 0.1, 1.0]],
        lp: 4200
      )
      soft_clip(out)
    end

    def prophet(midi, vel, dur_s)
      f=midi_hz(midi); len=(dur_s*SAMPLE_RATE).to_i+1
      partials=[[1.0,0.78,1.0],[2.0,0.31,0.9],[3.0,0.18,0.75],[4.0,0.10,0.62],[5.0,0.045,0.5]]
      a=Dilla.render_tone(len,f,0.58*vel,env:{attack:0.025,decay:@voice.fetch("decay",3.8).to_f,sustain:0.36},partials:partials,lp:1700+4400*@voice.fetch("brightness",0.5).to_f)
      b=Dilla.render_tone(len,f*1.0032,0.42*vel,env:{attack:0.035,decay:@voice.fetch("decay",3.8).to_f,sustain:0.32},partials:partials,lp:1500+4100*@voice.fetch("brightness",0.5).to_f)
      len.times { |i| a[i]=a[i]*0.62+b[i]*0.38 }; soft_clip(a)
    end

    def juno(midi, vel, dur_s)
      f=midi_hz(midi); len=(dur_s*SAMPLE_RATE).to_i+1
      partials=[[1.0,0.62,1.0],[2.0,0.28,0.85],[3.0,0.18,0.7],[4.0,0.10,0.55],[5.0,0.05,0.4]]
      a=Dilla.render_tone(len,f,0.56*vel,env:{attack:0.18,decay:@voice.fetch("decay",6.5).to_f,sustain:0.58},partials:partials,lp:1100+3300*@voice.fetch("brightness",0.4).to_f)
      b=Dilla.render_tone(len,f*1.006,0.44*vel,env:{attack:0.22,decay:@voice.fetch("decay",6.5).to_f,sustain:0.55},partials:partials,lp:1000+3000*@voice.fetch("brightness",0.4).to_f)
      depth=@voice.fetch("ensemble",0.08).to_f; rate=@voice.fetch("ensemble_rate",0.23).to_f
      len.times { |i| a[i]=(a[i]*0.56+b[i]*0.44)*(1.0-depth*(0.5-0.5*Math.sin(2.0*Math::PI*rate*i/SAMPLE_RATE))) }
      soft_clip(a)
    end

    def minimoog(midi, vel, dur_s)
      f=midi_hz(midi); len=(dur_s*SAMPLE_RATE).to_i+1
      partials=[[1.0,0.95,1.0],[2.0,0.38,0.82],[3.0,0.22,0.68],[4.0,0.13,0.5],[5.0,0.075,0.36],[6.0,0.035,0.25]]
      out=Dilla.render_tone(len,f,0.78*vel,env:{attack:0.004,decay:@voice.fetch("decay",1.1).to_f,sustain:0.18},partials:partials,lp:@voice.fetch("cutoff",2400).to_f)
      soft_clip(out,1.2)
    end

    def wurlitzer(midi, vel, dur_s)
      f=midi_hz(midi); len=(dur_s*SAMPLE_RATE).to_i+1
      out=Dilla.render_tone(len,f,0.84*vel,env:{attack:0.004,decay:@voice.fetch("decay",1.65).to_f,sustain:0.07},
        partials:[[1.0,1.0,1.0],[2.01,0.25,0.42],[3.96,0.12,0.24],[6.13,0.04,0.12]],lp:3300+1800*@voice.fetch("brightness",0.45).to_f)
      soft_clip(out)
    end

    def fm_glass(midi, vel, dur_s)
      f=midi_hz(midi); len=(dur_s*SAMPLE_RATE).to_i+1
      ratio=@voice.fetch("fm_ratio",2.71).to_f; index=@voice.fetch("fm_index",4.0).to_f
      mod_phase=0.0; car_phase=0.0; mod_inc=f*ratio*65_536.0/SAMPLE_RATE; car_inc=f*65_536.0/SAMPLE_RATE
      decay=Math.exp(-1.0/(@voice.fetch("decay",0.8).to_f.clamp(0.05,10.0)*SAMPLE_RATE))
      out=Array.new(len,0.0)
      len.times do |i|
        phase=car_phase+Math.sin(mod_phase)*index*65_536.0/(2.0*Math::PI)
        out[i]=Dilla.sine(phase.round)*(decay**i)*vel
        mod_phase+=mod_inc; car_phase+=car_inc
      end
      soft_clip(out,1.02)
    end

    def chord_note(midi, vel, dur_s)
      case @voice["type"]
      when "rhodes" then rhodes(midi, vel, dur_s)
      when "pad" then pad(midi, vel, dur_s)
      when "musicbox" then musicbox(midi, vel, dur_s)
      when "prophet" then prophet(midi, vel, dur_s)
      when "juno" then juno(midi, vel, dur_s)
      when "minimoog" then minimoog(midi, vel, dur_s)
      when "wurlitzer" then wurlitzer(midi, vel, dur_s)
      when "fm" then fm_glass(midi, vel, dur_s)
      else organ(midi, vel, dur_s)
      end
    end

    def morph_note(midi, vel, dur_s, target_voice, amount)
      source=chord_note(midi,vel,dur_s)
      target=self.class.new(@kit,target_voice,@theory).chord_note(midi,vel,dur_s)
      mix=amount.to_f.clamp(0.0,1.0); length=[source.length,target.length].max
      Array.new(length) { |i| (source[i] || 0.0)*(1.0-mix)+(target[i] || 0.0)*mix }
    end

    # Fingered electric bass: fundamentals plus a bit of 2nd/3rd harmonic,
    # plucked envelope, low-passed, gentle saturation.
    def bass(midi, vel, dur_s)
      f = midi_hz(midi)
      len = (dur_s * SAMPLE_RATE).to_i + 1
      out = Dilla.render_tone(
        len, f, 1.3 * vel,
        env: { attack: 0.005, decay: [dur_s * 0.9, 0.5].max, sustain: 0.3 },
        # Reference bass stems measure ~93% low share but a ~660 Hz centroid:
        # the fundamentals dominate, yet the 2nd-4th harmonics are clearly
        # audible. The old near-sine tone measured a ~320 Hz centroid.
        partials: [[1.0, 1.0, 1.0], [2.0, 0.45, 0.65], [3.0, 0.34, 0.5], [4.0, 0.18, 0.35]],
        lp: 1150
      )
      soft_clip(out, 1.35)
    end

    def midi_hz(midi)
      440.0 * (2.0**((midi - 69) / 12.0))
    end

    def soft_clip(buffer, drive = 1.1)
      i = 0
      n = buffer.length
      while i < n
        x = buffer[i] * drive
        buffer[i] = x / (1.0 + x.abs) * 1.4 if x.abs > 0.2
        i += 1
      end
      buffer
    end
  end
end

module Dilla
  # ------------------------------------------------------------- drums

  class DrumKit
    def initialize(kit)
      @kit = kit
    end

    # SP-12 style kick: pitch drops fast into the forties, click transient on
    # top, tanh saturation, 12-bit quantize. The 40 Hz sub layer is rendered
    # separately by the sequencer so it can gate against the mix.
    def kick(vel)
      tune = @kit["kick"]["tune"].to_f
      decay = @kit["kick"]["decay"].to_f
      tone = @kit["kick"]["tone"].to_f
      base = 52.0 * (2.0**(tune / 12.0))
      len = (decay * SAMPLE_RATE).to_i + 1
      out = Array.new(len, 0.0)
      phase = 0.0
      mod_phase = 0.0
      attack = 24
      drop_coef = Math.exp(-1.0 / (0.045 * SAMPLE_RATE))
      decay_coef = Math.exp(-1.0 / (decay * 0.38 * SAMPLE_RATE))
      fm_ratio = @kit["kick"].fetch("fm_ratio", 2.37).to_f
      fm_index = @kit["kick"].fetch("fm_index", 3.7).to_f
      fm_decay = Math.exp(-1.0 / (@kit["kick"].fetch("fm_decay", 0.018).to_f.clamp(0.002, 0.2) * SAMPLE_RATE))
      freq = base * 2.6
      click_len = (0.004 * SAMPLE_RATE).to_i
      i = 0
      while i < len
        env = i < attack ? i / attack.to_f : decay_coef**(i - attack)
        f = base + (freq - base) * drop_coef**i
        phase += f * 65_536 / SAMPLE_RATE
        mod_phase += f * fm_ratio * 65_536 / SAMPLE_RATE
        index = fm_index * (fm_decay**i) + 0.10
        modulated_phase = phase + Math.sin(mod_phase) * index * 65_536.0 / (2.0 * Math::PI)
        s = Dilla.sine(modulated_phase.round)
        s = Math.tanh(s * 1.6) * 0.85
        s += NOISE[(i * 7 + 11) % NOISE.length] * (i < click_len ? 0.22 * (1.0 - i / click_len.to_f) : 0.0)
        out[i] = s * env * vel * 0.95
        i += 1
      end
      tone_shape!(out, tone, 5200)
      crush!(out, @kit["kick"]["crush"])
      out
    end

    def snare(vel)
      tune = @kit["snare"]["tune"].to_f
      decay = @kit["snare"]["decay"].to_f
      tone = @kit["snare"]["tone"].to_f
      len = (decay * SAMPLE_RATE * 1.6).to_i + 1
      out = Array.new(len, 0.0)
      body_f = 186.0 * (2.0**(tune / 12.0))
      noise_decay = Math.exp(-1.0 / (decay * 0.30 * SAMPLE_RATE))
      body_decay = Math.exp(-1.0 / (0.075 * SAMPLE_RATE))
      phase = 0.0
      mod_phase = 0.0
      fm_ratio = @kit["snare"].fetch("fm_ratio", 2.82).to_f
      fm_index = @kit["snare"].fetch("fm_index", 2.4).to_f
      fm_decay = Math.exp(-1.0 / (@kit["snare"].fetch("fm_decay", 0.023).to_f.clamp(0.002, 0.2) * SAMPLE_RATE))
      off = Random.rand(NOISE.length / 2)
      i = 0
      while i < len
        env_n = noise_decay**i
        env_b = body_decay**i
        noise = NOISE[(i + off) % NOISE.length] * env_n
        phase += body_f * 65_536 / SAMPLE_RATE
        mod_phase += body_f * fm_ratio * 65_536 / SAMPLE_RATE
        index = fm_index * (fm_decay**i) + 0.08
        modulated_phase = phase + Math.sin(mod_phase) * index * 65_536.0 / (2.0 * Math::PI)
        body = Dilla.sine(modulated_phase.round) * env_b
        crack = i < 90 ? NOISE[(i * 3 + off) % NOISE.length] * (1.0 - i / 90.0) * 0.6 : 0.0
        out[i] = (noise * (0.42 + 0.3 * tone) + body * 0.55 + crack) * vel
        i += 1
      end
      highpass!(out, 320.0)
      tone_shape!(out, tone, 4600)
      crush!(out, @kit["snare"]["crush"])
      out
    end

    def hat(vel, open: false)
      decay = open ? @kit["openhat"]["decay"].to_f : @kit["hat"]["decay"].to_f * (0.7 + 0.6 * vel)
      len = (decay * SAMPLE_RATE).to_i + 1
      out = Array.new(len, 0.0)
      decay_coef = Math.exp(-1.0 / (decay * 0.32 * SAMPLE_RATE))
      fm_ratio = @kit["hat"].fetch("fm_ratio", 1.414).to_f
      fm_index = @kit["hat"].fetch("fm_index", 1.2).to_f
      fm_decay = Math.exp(-1.0 / (@kit["hat"].fetch("fm_decay", 0.0045).to_f.clamp(0.001, 0.1) * SAMPLE_RATE))
      operator_hz = [5_700.0, 7_150.0, 8_660.0, 10_430.0]
      operator_weights = [0.34, 0.28, 0.22, 0.16]
      carrier_phases = Array.new(operator_hz.length, 0.0)
      modulator_phases = Array.new(operator_hz.length, 0.0)
      off = Random.rand(NOISE.length / 2)
      speed = 0.97 + Random.rand * 0.06
      i = 0
      while i < len
        noise = NOISE[((i * speed).floor + off) % NOISE.length]
        metallic = 0.0
        operator_hz.each_with_index do |hz, operator|
          carrier_phases[operator] += hz * 65_536 / SAMPLE_RATE
          modulator_phases[operator] += hz * fm_ratio * 65_536 / SAMPLE_RATE
          index = fm_index * (fm_decay**i) * (1.0 + operator * 0.12)
          phase = carrier_phases[operator] +
                  Math.sin(modulator_phases[operator]) * index * 65_536.0 / (2.0 * Math::PI)
          metallic += Dilla.sine(phase.round) * operator_weights[operator]
        end
        out[i] = (noise * 0.68 + metallic * 0.18) * (decay_coef**i) * vel
        i += 1
      end
      highpass!(out, 6200.0)
      highpass!(out, 4200.0)
      # Reference stems sit dark: hats carry almost nothing above ~4 kHz on
      # the records this engine imitates, so a gentle post-highpass shelf
      # keeps the tick but loses the fizz.
      tone_shape!(out, 0.18, 8600)
      tone_shape!(out, 0.5, 8600)
      crush!(out, @kit["hat"]["crush"])
      scale = open ? @kit["openhat"]["level"].to_f : @kit["hat"]["level"].to_f
      out.each_with_index { |v, idx| out[idx] = v * scale * 2.2 }
      out
    end

    def ride(vel)
      decay = @kit["ride"]["decay"].to_f
      len = (decay * SAMPLE_RATE).to_i + 1
      out = Array.new(len, 0.0)
      decay_coef = Math.exp(-1.0 / (decay * 0.3 * SAMPLE_RATE))
      off = Random.rand(NOISE.length / 2)
      i = 0
      while i < len
        s = NOISE[(i + off) % NOISE.length]
        ping = Dilla.sine((2.0 * Math::PI * 990 * i / SAMPLE_RATE).round & 65_535) * 0.12
        out[i] = (s * 0.5 + ping) * (decay_coef**i) * vel
        i += 1
      end
      highpass!(out, 3400.0)
      tone_shape!(out, 0.35, 4200)
      out.each_with_index { |v, idx| out[idx] = v * @kit["ride"]["level"].to_f * 2.0 }
      out
    end

    def soulclap(vel)
      len = (0.18 * SAMPLE_RATE).to_i
      out = Array.new(len, 0.0)
      [0, 11, 27, 43].each_with_index do |offset, burst|
        duration = ([0.014, 0.021, 0.028, 0.036][burst] * SAMPLE_RATE).to_i
        pole = Math.exp(-2.0 * Math::PI * (1800.0 + burst * 520.0) / SAMPLE_RATE)
        state = 0.0
        duration.times do |j|
          index = offset + j
          break if index >= len
          noise = NOISE[(index * 13 + burst * 997) % NOISE.length]
          state += (noise - state) * (1.0 - pole)
          out[index] += state * Math.exp(-j.to_f / (duration * 0.32)) * (1.0 - burst * 0.13)
        end
      end
      crush!(out, @kit.dig("snare", "crush") || 12)
      out.map! { |sample| sample * vel * 0.42 }
    end

    def perc(vel)
      decay = @kit["perc"]["decay"].to_f
      len = (decay * SAMPLE_RATE * 2).to_i + 1
      out = Array.new(len, 0.0)
      decay_coef = Math.exp(-1.0 / (decay * 0.4 * SAMPLE_RATE))
      attack = (0.008 * SAMPLE_RATE).to_i
      off = Random.rand(NOISE.length / 2)
      i = 0
      while i < len
        env = (i < attack ? i / attack.to_f : 1.0) * (decay_coef**i)
        out[i] = NOISE[(i + off) % NOISE.length] * env * vel
        i += 1
      end
      bandpass_ish!(out, 3200.0, 0.6)
      out.each_with_index { |v, idx| out[idx] = v * @kit["perc"]["level"].to_f * 2.0 }
      out
    end

    # The 40 Hz sub: kick-gated sine with a short gate and release, exactly the
    # production-dna mix note ("40Hz oscillator triggered by kick").
    def sub(vel)
      hold = (0.045 * SAMPLE_RATE).to_i
      release = (0.12 * SAMPLE_RATE).to_i
      attack = (0.008 * SAMPLE_RATE).to_i
      len = hold + release
      out = Array.new(len, 0.0)
      f = 40.0 * (2.0**(@kit["sub"]["tune"].to_f / 12.0))
      inc = f * 65_536 / SAMPLE_RATE
      phase = 0
      i = 0
      while i < len
        # Fast 8 ms attack: the sub must hit WITH the kick, not trail it —
        # a slow ramp smears the low-band transient and shifts the whole
        # pocket measurement.
        env = if i < attack
                i.to_f / attack
              elsif i < hold
                1.0
              else
                1.0 - (i - hold).to_f / release
              end
        out[i] = Dilla.sine(phase) * env * env * vel
        phase += inc
        i += 1
      end
      out.each_with_index { |v, idx| out[idx] = v * @kit["sub"]["level"].to_f }
      out
    end

    # ---- per-hit shaping helpers

    def tone_shape!(buffer, tone, ceiling)
      lp = 1400.0 + (ceiling - 1400.0) * tone
      one_pole_lp!(buffer, lp)
    end

    def one_pole_lp!(buffer, hz)
      coef = Math.exp(-2.0 * Math::PI * hz / SAMPLE_RATE)
      state = 0.0
      i = 0
      n = buffer.length
      while i < n
        state += (buffer[i] - state) * (1.0 - coef)
        buffer[i] = state
        i += 1
      end
    end

    def highpass!(buffer, hz)
      lp = buffer.dup
      one_pole_lp!(lp, hz)
      i = 0
      n = buffer.length
      while i < n
        buffer[i] -= lp[i]
        i += 1
      end
    end

    def bandpass_ish!(buffer, center, width_q)
      low = buffer.dup
      one_pole_lp!(low, center)
      high = low.dup
      one_pole_lp!(high, center * (1.0 - width_q * 0.5))
      i = 0
      n = buffer.length
      while i < n
        buffer[i] = low[i] - high[i]
        i += 1
      end
    end

    # SP-1200 grit: 12-bit quantize per hit.
    def crush!(buffer, bits)
      return buffer unless bits && bits < 16

      levels = (2.0**(bits - 1))
      i = 0
      n = buffer.length
      while i < n
        buffer[i] = (buffer[i] * levels).round / levels
        i += 1
      end
      buffer
    end
  end

  # ------------------------------------------------------------- sample flip

  # Operator-supplied loop chopping: decode ≤24 s through local ffmpeg,
  # estimate each slice's pitch classes, pick chord-aware chops, and mix them
  # under the phrase starts before the final tape stage.
  module SampleFlip
    DEFAULT_VOL = 0.42
    DEFAULT_WEIGHT = 0.6
    DEFAULT_SLICES = 8
    MAX_SECONDS = 24.0

    module_function

    def decode(source)
      raw = Tempfile.new(["dilla_sample", ".raw"])
      cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
             "-i", source, "-t", MAX_SECONDS.to_s,
             "-ac", "1", "-ar", SAMPLE_RATE.to_s, "-f", "f32le", raw.path]
      out, err, status = Open3.capture3(*cmd)
      unless status.success?
        warn "dilla sample-flip: ffmpeg could not decode #{source}: #{err.lines.last.to_s.strip}"
        return nil
      end
      warn "dilla sample-flip: ffmpeg said #{out}" unless out.empty?
      data = File.binread(raw.path)
      data.unpack("e*")
    ensure
      raw&.close!
    end

    # Chroma via Goertzel: energy at each pitch class over harmonics 1-4.
    def chroma(samples, offset, length)
      step = 8 # decimate for speed
      n = (length / step).to_i
      base = { 0 => 65.41 } # C2
      chroma = Array.new(12, 0.0)
      12.times do |pc|
        energy = 0.0
        [1, 2, 3, 4].each do |h|
          f = 65.41 * (2.0**(pc / 12.0)) * h
          next if f > 4000

          coef = 2.0 * Math.cos(2.0 * Math::PI * f * step / SAMPLE_RATE)
          s1 = s2 = 0.0
          i = 0
          while i < n
            s = samples[offset + i * step] || 0.0
            s0 = s + coef * s1 - s2
            s2 = s1
            s1 = s0
            i += 1
          end
          power = s1 * s1 + s2 * s2 - coef * s1 * s2
          energy += Math.sqrt(power.clamp(0.0, 1.0 / 0.0))
        end
        chroma[pc] = energy
      end
      total = chroma.sum
      total.positive? ? chroma.map { |c| c / total } : chroma
    end

    def slices_for(samples, slice_count)
      slice_len = samples.length / slice_count
      slice_count.times.map do |idx|
        start = idx * slice_len
        { index: idx, start: start, length: slice_len, chroma: chroma(samples, start, slice_len) }
      end
    end

    def score_slice(slice, chord_pcs)
      score = 0.0
      chord_pcs.each do |pc|
        score += slice[:chroma][pc % 12]
      end
      score / chord_pcs.length
    end

    # Picks chops for the phrase plan: best-matching slice per chord slot,
    # never the same slice twice in a row, deterministic given the plan.
    def plan_chops(slice_data, chord_slots)
      chosen = []
      last = nil
      chord_slots.each do |pcs|
        ranked = slice_data.sort_by { |s| -score_slice(s, pcs) }
        pick = ranked.find { |s| s[:index] != last } || ranked.first
        chosen << pick
        last = pick[:index]
      end
      chosen
    end
  end
end

require "open3"
require "tempfile"

module Dilla
  # ------------------------------------------------------------- mix & render

  class Mixer
    attr_reader :duration_s

    def initialize(duration_s, rig, rng, bpm: 86.0)
      @n = (duration_s * SAMPLE_RATE).to_i + 1
      @duration_s = duration_s
      @rig = rig
      @rng = rng
      @bpm = bpm.to_f
      @buses = {
        drums: Stereo.new(@n), sub: Stereo.new(@n), bass: Stereo.new(@n),
        chords: Stereo.new(@n), melody: Stereo.new(@n), foley: Stereo.new(@n),
        sample: Stereo.new(@n), vinyl: Stereo.new(@n)
      }
      @gain = { drums: 1.4, sub: 0.8, bass: 1.25, chords: 0.38, melody: 0.36,
                foley: 0.30, sample: 0.5, vinyl: 0.0 }
    end

    attr_reader :buses

    def bus(name) = @buses.fetch(name)

    def gain!(name, db)
      @gain[name] = @gain.fetch(name) * (10.0**(db / 20.0)) if db && db != 0
    end

    def set_gain(name, value) = @gain[name] = value

    # Kick envelope on a 1 ms grid drives the sidechain duck. The bed breathes
    # with the kick instead of pumping on a timer.
    def sidechain_curve!(drum_events, amount, release_ms)
      return Array.new((@n / 441), 1.0) if amount.to_f <= 0

      grid_n = @n / 441 + 2
      curve = Array.new(grid_n, 0.0)
      drum_events.each do |ev|
        next unless ev.lane == :kick

        start = (ev.time * 1000).to_i
        len = [(release_ms + 60).to_i, 260].min
        i = 0
        while i < len
          idx = start + i
          break if idx >= grid_n

          v = (1.0 - i.to_f / len)
          curve[idx] = [curve[idx], v * ev.vel].max
          i += 1
        end
      end
      curve.map { |v| 1.0 - amount * v }
    end

    def duck!(bus_name, curve)
      b = bus(bus_name)
      i = 0
      n = b.l.length
      while i < n
        g = curve[i / 441] || 1.0
        b.l[i] *= g
        b.r[i] *= g
        i += 1
      end
    end

    # Vinyl bed: filtered noise plus deterministic crackle spikes. Level from
    # the rig, scaled by --vcs (vinyl-crackle saturation, 0..1).
    def render_vinyl(vcs)
      level = @rig.dig("vinyl", "level").to_f * (0.35 + 0.65 * vcs.to_f.clamp(0.0, 1.0))
      crackle = @rig.dig("vinyl", "crackle").to_f
      @gain[:vinyl] = level
      [0, 1].each do |ch|
        b = ch.zero? ? @buses[:vinyl].l : @buses[:vinyl].r
        off = @rng.rand(NOISE.length / 2)
        i = 0
        n = b.length
        lp = 0.0
        coef = Math.exp(-2.0 * Math::PI * 6200.0 / SAMPLE_RATE)
        next_spike = 2205 + @rng.rand(30_000)
        while i < n
          lp += (NOISE[(i + off) % NOISE.length] - lp) * (1.0 - coef)
          s = lp * 0.6
          if i >= next_spike
            s += (NOISE[(i * 5 + off) % NOISE.length]) * (0.35 + 0.4 * @rng.rand)
            next_spike = i + 1100 + @rng.rand(34_000)
          end
          b[i] = s
          i += 1
        end
      end
    end

    # Dub delay on a send: tempo-synced, low-passed in the loop, feedback.
    def apply_delay(send_bus, into, time_div, feedback, lowpass, throw_prob, rng)
      b = @buses.fetch(send_bus)
      d = @buses.fetch(into)
      delay_n = [(time_div * 2.0 * 60.0 / @bpm * SAMPLE_RATE).to_i, 1].max
      loop_lp = 0.0
      coef = Math.exp(-2.0 * Math::PI * lowpass / SAMPLE_RATE)
      buf = Array.new(delay_n, 0.0)
      read = 0
      i = 0
      n = d.l.length
      while i < n
        s = (b.l[i] + b.r[i]) * 0.5
        if s.abs > 0.02 && rng.rand < throw_prob
          buf[read] = s
        end
        loop_lp += (buf[read] - loop_lp) * (1.0 - coef)
        buf[read] = loop_lp * feedback
        d.l[i] += loop_lp * 0.5
        d.r[i] += loop_lp * 0.42
        read += 1
        read = 0 if read >= delay_n
        i += 1
      end
    end

    # Small plate: two combs and one allpass per channel on a send.
    def apply_reverb(send_bus, into, size, level)
      b = @buses.fetch(send_bus)
      d = @buses.fetch(into)
      sizes = [1116, 1397].map { |s| (s * (0.6 + size)).to_i }
      ap_size = (331 * (0.6 + size)).to_i
      combs = sizes.map { |s| { buf: Array.new(s, 0.0), idx: 0 } }
      combs_r = sizes.map { |s| { buf: Array.new((s * 1.013).to_i, 0.0), idx: 0 } }
      ap = { buf: Array.new(ap_size, 0.0), idx: 0 }
      ap_r = { buf: Array.new(ap_size + 23, 0.0), idx: 0 }
      fb = 0.62 + size * 0.3
      i = 0
      n = d.l.length
      while i < n
        s = (b.l[i] + b.r[i]) * 0.5
        l = r = 0.0
        combs.each_with_index do |c, _|
          out = c[:buf][c[:idx]]
          c[:buf][c[:idx]] = s + out * fb
          l += out
        end
        combs_r.each_with_index do |c, _|
          out = c[:buf][c[:idx]]
          c[:buf][c[:idx]] = s + out * fb
          r += out
        end
        l *= 0.22
        r *= 0.22
        ap_out = ap[:buf][ap[:idx]]
        ap[:buf][ap[:idx]] = l - ap_out * 0.5
        l = ap_out + ap[:buf][ap[:idx]] * 0.5
        ap_out_r = ap_r[:buf][ap_r[:idx]]
        ap_r[:buf][ap_r[:idx]] = r - ap_out_r * 0.5
        r = ap_out_r + ap_r[:buf][ap_r[:idx]] * 0.5
        d.l[i] += l * level
        d.r[i] += r * level
        combs.each { |c| c[:idx] += 1; c[:idx] = 0 if c[:idx] >= c[:buf].length }
        combs_r.each { |c| c[:idx] += 1; c[:idx] = 0 if c[:idx] >= c[:buf].length }
        ap[:idx] += 1; ap[:idx] = 0 if ap[:idx] >= ap[:buf].length
        ap_r[:idx] += 1; ap_r[:idx] = 0 if ap_r[:idx] >= ap_r[:buf].length
        i += 1
      end
    end

    def mixdown
      mix = Stereo.new(@n)
      @buses.each do |name, b|
        g = @gain.fetch(name)
        next if g.zero?

        i = 0
        ml = mix.l
        mr = mix.r
        bl = b.l
        br = b.r
        while i < @n
          ml[i] += bl[i] * g
          mr[i] += br[i] * g
          i += 1
        end
      end
      mix
    end

    # Post-gain RMS: the share the mix actually carries, not the raw bus.
    def rms(bus_name)
      b = bus(bus_name)
      g = @gain.fetch(bus_name, 1.0)
      sum = 0.0
      i = 0
      n = b.l.length
      step = 4
      count = 0
      while i < n
        v = (b.l[i] + b.r[i]) * 0.5 * g
        sum += v * v
        count += 1
        i += step
      end
      count.positive? ? Math.sqrt(sum / count) : 0.0
    end
  end
end

module Dilla
  # ------------------------------------------------------------- master chain

  module Master
    module_function

    def dc_block!(mix)
      hp_l = hp_r = 0.0
      prev_l = prev_r = 0.0
      coef = Math.exp(-2.0 * Math::PI * 18.0 / SAMPLE_RATE)
      i = 0
      n = mix.l.length
      while i < n
        l = mix.l[i]
        r = mix.r[i]
        hp_l = l - prev_l + coef * hp_l
        hp_r = r - prev_r + coef * hp_r
        prev_l = l
        prev_r = r
        mix.l[i] = hp_l
        mix.r[i] = hp_r
        i += 1
      end
    end

    def tilt!(mix, db_low)
      gain = 10.0**(db_low / 20.0)
      coef = Math.exp(-2.0 * Math::PI * 180.0 / SAMPLE_RATE)
      [mix.l, mix.r].each do |ch|
        state = 0.0
        i = 0
        n = ch.length
        while i < n
          state += (ch[i] - state) * (1.0 - coef)
          ch[i] += state * (gain - 1.0)
          i += 1
        end
      end
    end

    def saturate!(mix, drive)
      i = 0
      n = mix.l.length
      while i < n
        mix.l[i] = Math.tanh(mix.l[i] * drive)
        mix.r[i] = Math.tanh(mix.r[i] * drive)
        i += 1
      end
    end

    # Boom-bap sits quieter than a brick-walled master: pull hot renders back
    # toward the genre's loudness instead of normalizing into the red. A quiet
    # render is returned untouched — the reference is a ceiling, not a floor.
    def steer_to_reference!(mix, reference: -9.5)
      lufs = lufs_estimate(mix)
      return lufs if lufs <= reference

      trim = 10.0**((reference - lufs) / 20.0)
      i = 0
      n = mix.l.length
      while i < n
        mix.l[i] *= trim
        mix.r[i] *= trim
        i += 1
      end
      lufs_estimate(mix)
    end

    def normalize!(mix, ceiling = 0.94)
      peak = 0.0
      i = 0
      n = mix.l.length
      while i < n
        p = mix.l[i].abs
        p = mix.r[i].abs if mix.r[i].abs > p
        peak = p if p > peak
        i += 1
      end
      return mix if peak.zero?

      g = ceiling / peak
      i = 0
      while i < n
        mix.l[i] *= g
        mix.r[i] *= g
        i += 1
      end
      mix
    end

    def fades!(mix, fade_in_s = 0.02, fade_out_s = 1.4)
      n = mix.l.length
      fi = (fade_in_s * SAMPLE_RATE).to_i
      fo = (fade_out_s * SAMPLE_RATE).to_i
      i = 0
      while i < fi && i < n
        g = i.to_f / fi
        mix.l[i] *= g
        mix.r[i] *= g
        i += 1
      end
      i = 0
      while i < fo && i < n
        g = i.to_f / fo
        idx = n - 1 - i
        mix.l[idx] *= g
        mix.r[idx] *= g
        i += 1
      end
    end

    # K-weighted loudness estimate: high shelf +4 dB at 1.5 kHz, 38 Hz
    # high-pass, then gated mean square. Close enough to steer by.
    def lufs_estimate(mix)
      shelf_coef = Math.exp(-2.0 * Math::PI * 1000.0 / SAMPLE_RATE)
      hp_coef = Math.exp(-2.0 * Math::PI * 38.0 / SAMPLE_RATE)
      state = prev = hp_state = hp_prev = 0.0
      sum = 0.0
      count = 0
      i = 0
      n = mix.l.length
      mono = Array.new(n / 2, 0.0)
      while i < n
        m = (mix.l[i] + mix.r[i]) * 0.5
        state += (m - state) * (1.0 - shelf_coef)
        shelf = m + (m - state) * 0.58
        hp = shelf - hp_prev + hp_coef * hp_state
        hp_prev = shelf
        hp_state = hp
        mono[i / 2] = hp
        sum += hp * hp
        count += 1
        i += 2
      end
      # Absolute-gate at -70 LUFS, then relative gate at -10 below the mean.
      mean_sq = sum / [count, 1].max
      lufs = -0.691 + 10.0 * Math.log10(mean_sq.clamp(1e-12, 1e12))
      threshold = lufs - 10.0
      sum2 = 0.0
      count2 = 0
      i = 0
      while i < mono.length
        v = mono[i]
        block = -0.691 + 10.0 * Math.log10((v * v).clamp(1e-12, 1e12))
        if block > threshold
          sum2 += v * v
          count2 += 1
        end
        i += 100
      end
      return lufs if count2.zero?

      -0.691 + 10.0 * Math.log10((sum2 / count2).clamp(1e-12, 1e12))
    end
  end

  # ------------------------------------------------------------- sonitex

  module Sonitex
    module_function

    # One pass of wear: filters, drive, bit depth, wow (slow pitch drift via a
    # re-read of one channel), crackle and hiss, dropouts. instances compound.
    def apply!(mix, preset, instances, rng)
      cfg = Dilla.catalogue.fetch("sonitex").fetch(preset) do
        warn "dilla: unknown sonitex preset #{preset.inspect}; skipping wear"
        return
      end
      instances.to_i.clamp(1, 6).times do |index|
        one_pass!(mix, index.zero? ? cfg : vary(cfg, rng), rng)
      end
      wow_flutter!(mix, cfg, rng)
      head_bump!(mix, cfg)
    end

    # Later instances compound a slightly different wear profile. Variation
    # comes from the render's seeded RNG, so identical seeds still reproduce.
    def vary(cfg, rng)
      cfg.merge(
        "drive" => cfg.fetch("drive", 1.0).to_f * (0.90 + rng.rand * 0.20),
        "lowpass" => cfg.fetch("lowpass", 12_000).to_f * (0.95 + rng.rand * 0.10),
        "wow" => cfg.fetch("wow", 0.0).to_f * (0.70 + rng.rand * 0.60),
        "crackle" => cfg.fetch("crackle", 0.0).to_f * (0.85 + rng.rand * 0.30),
        "hiss" => cfg.fetch("hiss", 0.0).to_f * (0.85 + rng.rand * 0.30)
      )
    end

    def one_pass!(mix, cfg, rng)
      one_pole_hp!(mix.l, cfg["highpass"])
      one_pole_hp!(mix.r, cfg["highpass"])
      one_pole_lp!(mix.l, cfg["lowpass"])
      one_pole_lp!(mix.r, cfg["lowpass"])
      drive = cfg["drive"].to_f
      bits = cfg["bits"].to_i
      levels = 2.0**([bits, 16].min - 1)
      n = mix.l.length
      i = 0
      while i < n
        l = mix.l[i] * drive
        r = mix.r[i] * drive
        l = Math.tanh(l)
        r = Math.tanh(r)
        l = (l * levels).round / levels
        r = (r * levels).round / levels
        mix.l[i] = l
        mix.r[i] = r
        i += 1
      end
      crackle!(mix, cfg["crackle"].to_f, rng)
      hiss!(mix, cfg["hiss"].to_f, rng)
      dropouts!(mix, cfg["dropout"].to_f, rng) if cfg["dropout"].to_f.positive?
    end

    # Tape speed instability moves sample position (pitch/time), not channel
    # amplitude. Bounded sinusoidal offsets avoid drift and preserve endpoints.
    def wow_flutter!(mix, cfg, rng)
      wow = cfg["wow"].to_f * 0.00035
      flutter = cfg.fetch("flutter", 0.35).to_f * 0.00008
      return if wow <= 0 && flutter <= 0
      phases = [rng.rand * 2.0 * Math::PI, rng.rand * 2.0 * Math::PI]
      [mix.l, mix.r].each_with_index do |channel, side|
        source = channel.dup
        w0 = Math.sin(phases[0] + side * 0.29)
        f0 = Math.sin(phases[1] + side * 0.41)
        wow_amp = wow * SAMPLE_RATE / (2.0 * Math::PI * 0.55)
        flutter_amp = flutter * SAMPLE_RATE / (2.0 * Math::PI * 5.7)
        channel.each_index do |i|
          t = i.to_f / SAMPLE_RATE
          offset = wow_amp * (Math.sin(2.0 * Math::PI * 0.55 * t + phases[0] + side * 0.29) - w0) +
                   flutter_amp * (Math.sin(2.0 * Math::PI * 5.7 * t + phases[1] + side * 0.41) - f0)
          position = (i + offset).clamp(0.0, source.length - 1.0)
          left = position.floor
          fraction = position - left
          right = [left + 1, source.length - 1].min
          channel[i] = source[left] * (1.0 - fraction) + source[right] * fraction
        end
      end
    end

    def head_bump!(mix, cfg)
      db = cfg.fetch("head_bump_db", 0.0).to_f
      return if db.abs < 0.001
      gain = 10.0**(db / 20.0)
      coefficient = Math.exp(-2.0 * Math::PI * cfg.fetch("head_bump_hz", 65.0).to_f / SAMPLE_RATE)
      [mix.l, mix.r].each do |channel|
        state = 0.0
        channel.each_index do |i|
          state += (channel[i] - state) * (1.0 - coefficient)
          channel[i] += state * (gain - 1.0)
        end
      end
    end

    def crackle!(mix, amount, rng)
      return if amount <= 0

      n = mix.l.length
      next_spike = 1000 + rng.rand(40_000)
      i = 0
      while i < n
        if i >= next_spike
          spike = (rng.rand * 2 - 1) * amount * 0.5
          mix.l[i] = (mix.l[i] + spike).clamp(-1.0, 1.0)
          mix.r[i] = (mix.r[i] + spike * 0.7).clamp(-1.0, 1.0)
          next_spike = i + 900 + rng.rand(44_000)
        end
        i += 1
      end
    end

    def hiss!(mix, amount, rng)
      return if amount <= 0

      n = mix.l.length
      i = 0
      # The noise entry point comes from the render's seeded rng: an unseeded
      # walk broke same-seed reproducibility once the noise buffer became a
      # real stream (before, the constant buffer masked any offset).
      off = rng.rand(NOISE.length)
      while i < n
        h = NOISE[(i + off) % NOISE.length] * amount * 0.06
        mix.l[i] += h
        mix.r[i] += h * 0.8
        i += 1
      end
    end

    def dropouts!(mix, amount, rng)
      n = mix.l.length
      next_drop = rng.rand(n / 2)
      i = 0
      while i < n
        if i >= next_drop
          len = 300 + rng.rand(900)
          j = 0
          g0 = 1.0 - amount * 2.0
          while j < len && i + j < n
            g = [g0, 0.0].max + (1.0 - g0) * (j.to_f / len)
            mix.l[i + j] *= g
            mix.r[i + j] *= g
            j += 1
          end
          i += len
          next_drop = i + rng.rand(n / 3)
        end
        i += 1
      end
    end

    def one_pole_lp!(ch, hz)
      coef = Math.exp(-2.0 * Math::PI * hz / SAMPLE_RATE)
      state = 0.0
      i = 0
      n = ch.length
      while i < n
        state += (ch[i] - state) * (1.0 - coef)
        ch[i] = state
        i += 1
      end
    end

    def one_pole_hp!(ch, hz)
      lp = ch.dup
      one_pole_lp!(lp, hz)
      i = 0
      n = ch.length
      while i < n
        ch[i] -= lp[i]
        i += 1
      end
    end
  end

  # Dependency-free Standard MIDI writer: export the exact score events that
  # the local Ruby renderer plays, with no gem or hosted API dependency.
  module MidiWriter
    PPQN = 960
    DRUM_NOTES = { kick: 36, snare: 38, ghost: 38, hats: 42, open_hat: 46,
                   ride: 51, perc: 75, soulclap: 39 }.freeze
    LANES = [[:conductor, 0, "Tempo"], [:drum, 9, "Drums"], [:chord, 0, "Harmony"],
             [:bass, 1, "Bass"], [:melody, 2, "Melody"], [:foley, 3, "Electronic Foley"]].freeze
    module_function

    def write(path, events, bpm:)
      tempo = (60_000_000.0 / bpm.to_f).round
      tracks = LANES.map do |lane, channel, name|
        rows = lane == :conductor ? [] : Array(events[lane]).flat_map { |event| note_rows(lane, channel, event, bpm) }
        track_chunk(name, rows, tempo: lane == :conductor ? tempo : nil)
      end
      Dilla.atomic_write(path, "MThd".b + [6, 1, tracks.length, PPQN].pack("Nnnn") + tracks.join, binary: true)
      path
    end

    def note_rows(lane, channel, event, bpm)
      notes = if lane == :drum
                [[DRUM_NOTES.fetch(event.lane, 37), 0.06]]
              elsif event.midi.is_a?(Array)
                event.midi.map { |note| [note, event.dur] }
              elsif event.midi
                [[event.midi, event.dur]]
              else
                []
              end
      notes.flat_map do |note, duration|
        start_tick = [(event.time.to_f * bpm.to_f * PPQN / 60.0).round, 0].max
        end_tick = [((event.time.to_f + [duration.to_f, 0.055].max) * bpm.to_f * PPQN / 60.0).round, start_tick + 1].max
        pitch = note.to_i.clamp(0, 127)
        velocity = (event.vel.to_f * 127).round.clamp(1, 127)
        [[start_tick, 1, [0x90 | channel, pitch, velocity].pack("C*")],
         [end_tick, 0, [0x80 | channel, pitch, 0].pack("C*")]]
      end
    end

    def track_chunk(name, rows, tempo: nil)
      name = name.to_s.b
      events = [[0, -2, [0xff, 0x03, name.bytesize].pack("C*") + name]]
      if tempo
        events << [0, -1, [0xff, 0x51, 0x03, (tempo >> 16) & 0xff, (tempo >> 8) & 0xff, tempo & 0xff].pack("C*")]
        events << [0, -1, [0xff, 0x58, 0x04, 4, 2, 24, 8].pack("C*")]
      end
      events.concat(rows)
      events.sort_by! { |tick, priority, _| [tick, priority] }
      body = String.new(encoding: Encoding::BINARY)
      previous = 0
      events.each do |tick, _priority, bytes|
        body << variable_length([tick - previous, 0].max)
        body << bytes
        previous = tick
      end
      body << "\x00\xff\x2f\x00".b
      "MTrk".b + [body.bytesize].pack("N") + body
    end

    def variable_length(value)
      buffer = value.to_i & 0x7f
      while (value >>= 7).positive?
        buffer = (buffer << 8) | ((value & 0x7f) | 0x80)
      end
      bytes = String.new(encoding: Encoding::BINARY)
      loop do
        byte = buffer & 0xff
        bytes << byte
        break if (byte & 0x80).zero?
        buffer >>= 8
      end
      bytes
    end
  end

  # ------------------------------------------------------------- WAV IO

  module Wav
    module_function

    def write_16bit(path, mix, sample_rate: SAMPLE_RATE)
      n = mix.l.length
      data = String.new(capacity: n * 4)
      pack_buf = Array.new(2)
      i = 0
      while i < n
        l = (mix.l[i].clamp(-1.0, 1.0) * 32_767).round
        r = (mix.r[i].clamp(-1.0, 1.0) * 32_767).round
        data << [l, r].pack("s<s<")
        i += 1
      end
      header = build_header(sample_rate, 2, 16, data.bytesize)
      Dilla.atomic_write(path, header + data, binary: true)
      path
    end

    def build_header(sample_rate, channels, bits, data_bytes)
      byte_rate = sample_rate * channels * bits / 8
      block_align = channels * bits / 8
      ["RIFF", 36 + data_bytes, "WAVE", "fmt ", 16, 1, channels, sample_rate, byte_rate, block_align, bits, "data", data_bytes].pack("A4VA4A4VvvVVvvA4V")
    end
  end
end

module Dilla
  module_function

  # ------------------------------------------------------------- orchestration

  DEFAULT_DRUMS_FOR_STYLE = {
    "j_dilla" => "dilla_shadow_full",
    "general" => "boom_bap"
  }.freeze

  def resolve_render_plan(opts, showcase: nil)
    profiles = catalogue.fetch("production_profiles", {})
    style = profiles.fetch(opts.style.to_s, {})
    progression_ref = opts.progression || style["progression"] ||
                      (showcase && showcase["progression"]) || showcase_data.fetch("progression")
    prog = progression_by_ref(progression_ref)
    drum_patterns = catalogue.fetch("drum_patterns").keys.reject { |k| k == "comment" }
    drum_candidate = opts.drums || style["drums"] || DEFAULT_DRUMS_FOR_STYLE.fetch("j_dilla")
    drums = drum_patterns.include?(drum_candidate) ? drum_candidate : DEFAULT_DRUMS_FOR_STYLE.fetch("j_dilla")
    kits = catalogue.fetch("kits").keys.reject { |k| k == "comment" }
    kit_candidate = opts.kit || style["kit"] || "kit_dust"
    kit = kits.include?(kit_candidate) ? kit_candidate : "kit_dust"
    voice_candidate = opts.voice || style["voice"] || "rhodes_mark1"
    voice = catalogue.fetch("voices").key?(voice_candidate) ? voice_candidate : "rhodes_mark1"
    rigs = catalogue.fetch("rigs").keys.reject { |k| k == "comment" }
    rig_candidate = opts.rig || style["rig"] || "dilla_night"
    rig = rigs.include?(rig_candidate) ? rig_candidate : "dilla_night"
    sonitex_presets = catalogue.fetch("sonitex").keys.reject { |k| k == "comment" }
    wear_candidate = opts.sonitex || style["sonitex"] || "subtle"
    sonitex = sonitex_presets.include?(wear_candidate) ? wear_candidate : "subtle"
    # An explicit recording's own tempo outranks the generic style preset.
    bpm = (opts.bpm || prog["bpm"] || style["bpm"]).to_f.clamp(50.0, 200.0)
    arrangement = showcase && Array(showcase["arrangement"]).any? ? showcase["arrangement"] : nil
    arrangement_bars = Array(arrangement).sum { |section| section.fetch("bars", 0).to_i }
    bars = (opts.bars || (arrangement_bars.positive? ? arrangement_bars : nil) ||
            prog["bars"] || catalogue.dig("defaults", "bars")).to_i.clamp(1, 128)
    feel = prog["feel"] || {}
    groove_profiles = catalogue.fetch("groove_profiles")
    groove_candidate = opts.profile || style["groove_profile"] || "dilla_shadow"
    groove_profile = groove_profiles.key?(groove_candidate) ? groove_candidate : "dilla_shadow"
    swing = feel.fetch("swing", 54.0).to_f
    performers = catalogue.fetch("performers")
    performer = opts.performer && performers.any? { |p| p["id"] == opts.performer } ? opts.performer : nil
    {
      progression: prog, drums: drums, kit: kit, voice: voice, rig: rig, sonitex: sonitex,
      bpm: bpm, bars: bars, profile: groove_profile, swing: swing, performer_id: performer,
      arrangement: arrangement,
      vcs: (opts.vcs || 0.54).to_f.clamp(0.0, 1.0),
      groove_scale: opts.groove ? opts.groove.to_f.clamp(0.85, 1.25) : 1.0,
      sonitex_instances: (opts.sonitex_instances || 1).to_i.clamp(1, 6)
    }
  end

  def render(opts, showcase: nil, quiet: false)
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    plan = resolve_render_plan(opts, showcase:)
    rng = Rng.new(opts.seed)
    srand(rng.seed)
    performers = catalogue.fetch("performers")
    performer = performers.find { |p| p["id"] == plan[:performer_id] } || rng.pick(performers)
    profile = catalogue.fetch("groove_profiles").fetch(plan[:profile]).dup
    profile["spread_ms"] = (profile["spread_ms"].to_f * plan[:groove_scale]).round(2)
    groove = Groove.new(bpm: plan[:bpm], swing: plan[:swing] + performer.fetch("swing_bias", 0.0), profile: profile, performer: performer)
    kit = catalogue.fetch("kits").fetch(plan[:kit])
    voice = catalogue.fetch("voices").fetch(plan[:voice])
    rig = catalogue.fetch("rigs").fetch(plan[:rig])
    drums_cfg = catalogue.fetch("drum_patterns").fetch(plan[:drums])

    bar_count = plan[:bars]
    tail_s = 2.6
    duration = bar_count * groove.bar_s + tail_s
    mixer = Mixer.new(duration, rig, rng, bpm: plan[:bpm])
    instruments = Instruments.new(kit, voice, theory)
    drum_kit = DrumKit.new(kit)
    seq = Sequencer.new(
      progress: plan[:progression], groove:, drums: drums_cfg, rig:, rng:, performer:,
      opts: { bars: bar_count, arrangement: plan[:arrangement], foley: opts.foley }
    )
    events = seq.events

    # --- drums & sub
    drum_buf = Hash.new { |_h, k| raise KeyError, "no drum #{k}" }
    events.fetch(:drum).each do |ev|
      samples = case ev.lane
                when :kick then drum_kit.kick(ev.vel)
                when :snare, :ghost then drum_kit.snare(ev.vel)
                when :hats then drum_kit.hat(ev.vel)
                when :open_hat then drum_kit.hat(ev.vel, open: true)
                when :ride then drum_kit.ride(ev.vel)
                when :perc then drum_kit.perc(ev.vel)
                when :soulclap then drum_kit.soulclap(ev.vel)
                else next
                end
      pan = pan_for_lane(ev.lane, kit)
      mixer.bus(:drums).add_mono!((ev.time * SAMPLE_RATE).round, samples, 1.0 - [pan, 0.0].max, 1.0 + [pan, 0.0].min)
    end
    events.fetch(:drum).each do |ev|
      next unless ev.lane == :kick

      samples = drum_kit.sub(ev.vel)
      mixer.bus(:sub).add_mono!((ev.time * SAMPLE_RATE).round, samples, 0.9, 0.9)
    end

    # --- chords, bass, melody and chord-aware electronic accents
    render_note = lambda do |ev, midi, lane|
      meta = ev.meta.is_a?(Hash) ? ev.meta : {}
      voice_name = meta["voice"] || plan[:voice]
      config = catalogue.fetch("voices").fetch(voice_name)
      config = config.merge("brightness" => (config.fetch("brightness", 0.5).to_f + (lane == :melody ? 0.22 : 0.0)).clamp(0.0, 0.95))
      engine = (voice_name == plan[:voice] && lane != :melody) ? instruments : Instruments.new(kit, config, theory)
      target_name = meta["morph_to"]
      if target_name && meta.fetch("morph_mix", 0.0).to_f.positive?
        engine.morph_note(midi, ev.vel, ev.dur, catalogue.fetch("voices").fetch(target_name), meta["morph_mix"])
      else
        engine.chord_note(midi, ev.vel, ev.dur)
      end
    end
    events.fetch(:chord).each do |ev|
      voicing = ev.midi; start = (ev.time * SAMPLE_RATE).round
      event_voice = (ev.meta.is_a?(Hash) && ev.meta["voice"]) || plan[:voice]
      pan_base = catalogue.fetch("voices").fetch(event_voice).fetch("pan", 0.0).to_f
      voicing.each_with_index do |midi, idx|
        spread = voicing.length <= 1 ? 0.0 : (idx.to_f / (voicing.length - 1)) * 0.44 - 0.22
        pan = (spread + pan_base).clamp(-0.7, 0.7)
        mixer.bus(:chords).add_mono!(start, render_note.call(ev, midi, :chord), 1.0 - [pan, 0.0].max, 1.0 + [pan, 0.0].min)
      end
    end
    events.fetch(:bass).each do |ev|
      start = (ev.time * SAMPLE_RATE).round
      samples = instruments.bass(ev.midi, ev.vel, ev.dur)
      mixer.bus(:bass).add_mono!(start, samples, 0.95, 0.95)
    end
    events.fetch(:melody).each do |ev|
      start = (ev.time * SAMPLE_RATE).round
      samples = render_note.call(ev, ev.midi, :melody)
      pan = 0.18 + ((ev.midi % 5) - 2) * 0.06
      mixer.bus(:melody).add_mono!(start, samples, 1.0 - [pan, 0.0].max, 1.0 + [pan, 0.0].min)
    end
    foley_engine = Instruments.new(kit, catalogue.fetch("voices").fetch("fm_glass"), theory)
    events.fetch(:foley, []).each do |ev|
      start = (ev.time * SAMPLE_RATE).round
      samples = foley_engine.chord_note(ev.midi, ev.vel, ev.dur)
      pan = 0.22 + ((ev.midi % 7) - 3) * 0.045
      mixer.bus(:foley).add_mono!(start, samples, 0.46 - [pan, 0.0].max * 0.12, 0.46 + [pan, 0.0].min * 0.12)
    end

    # --- sample flip (operator-supplied, rights-cleared audio only)
    sample_report = apply_sample_flip!(mixer, opts, groove, plan)

    # --- balances & glue
    mixer.gain!(:drums, opts.drum_balance.to_f) if opts.drum_balance
    mixer.gain!(:chords, opts.chord_balance.to_f) if opts.chord_balance
    curve = mixer.sidechain_curve!(events.fetch(:drum), rig.dig("sidechain", "amount"), rig.dig("sidechain", "release_ms") || 120)
    %i[chords bass melody foley sample].each { |b| mixer.duck!(b, curve) }

    mixer.render_vinyl(plan[:vcs])
    delay = rig.fetch("delay")
    mixer.apply_delay(:melody, :melody, delay["time_div"], delay["feedback"], delay["lowpass"], delay["throw_melody"].to_f + 0.02, rng)
    mixer.apply_delay(:chords, :chords, delay["time_div"] * 2.0, delay["feedback"] * 0.5, delay["lowpass"] * 0.8, delay["throw_chords"].to_f, rng)
    mixer.apply_delay(:foley, :foley, delay["time_div"] * 0.5, delay["feedback"] * 0.42, delay["lowpass"] * 1.25, 0.24, rng) if events.fetch(:foley, []).any?
    reverb = rig.fetch("reverb")
    mixer.bus(:drums).l.each_index { |i| mixer.bus(:drums).l[i] } # no-op keeps arrays materialized
    mixer.apply_reverb(:melody, :melody, reverb["size"], reverb["level_melody"])
    mixer.apply_reverb(:chords, :chords, reverb["size"], reverb["level_chords"])
    mixer.apply_reverb(:foley, :foley, [reverb["size"].to_f + 0.12, 1.0].min, reverb["level_melody"].to_f * 1.25) if events.fetch(:foley, []).any?
    apply_snare_verb!(mixer, events, reverb)

    mix = mixer.mixdown
    Master.dc_block!(mix)
    Master.tilt!(mix, 0.8)
    Master.saturate!(mix, 1.08)
    Sonitex.apply!(mix, plan[:sonitex], plan[:sonitex_instances], rng)
    Master.normalize!(mix)
    Master.fades!(mix)
    lufs = Master.steer_to_reference!(mix)

    stem_shares = {
      "drums" => mixer.rms(:drums), "sub" => mixer.rms(:sub), "bass" => mixer.rms(:bass),
      "chords" => mixer.rms(:chords), "melody" => mixer.rms(:melody),
      "foley" => mixer.rms(:foley), "sample" => mixer.rms(:sample)
    }

    # --- write outputs + sidecars
    out_base = opts.out ? File.expand_path(opts.out) : File.join(ENGINE_ROOT, "demo")
    out_base = out_base.sub(/\.(wav|mp3)\z/, "")
    dir = File.dirname(out_base)
    FileUtils.mkdir_p(dir)
    wav_path = "#{out_base}.wav"
    Wav.write_16bit(wav_path, mix)
    midi_path = nil
    if opts.midi || !opts.midi_out.to_s.empty?
      midi_path = opts.midi_out.to_s.empty? ? "#{out_base}.mid" : File.expand_path(opts.midi_out)
      FileUtils.mkdir_p(File.dirname(midi_path))
      MidiWriter.write(midi_path, events, bpm: plan[:bpm])
    end
    quality = write_quality(out_base, mix, lufs, stem_shares, duration, plan)
    session = write_session(out_base, plan, performer, events, sample_report)
    provenance = write_provenance(out_base, opts, plan, performer, wav_path, session, quality)
    mp3_path = nil
    if opts.mp3 || opts.out.to_s.end_with?(".mp3") || opts.out.nil?
      mp3_path = "#{out_base}.mp3"
      ok, _err = encode_mp3(wav_path, mp3_path)
      mp3_path = nil unless ok
    end
    render_video(opts, wav_path) if opts.video

    seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    log = format("dilla %s: %s - %s / %s, %.1f BPM, %d bars, seed %s, performer %s, %.1fs render, LUFS %.1f",
                 VERSION, plan[:progression]["title"], plan[:drums], plan[:profile], plan[:bpm], bar_count,
                 rng.seed, performer["id"], seconds, lufs)
    puts log unless quiet
    { seed: rng.seed, performer: performer["id"], bpm: plan[:bpm], path: mp3_path || wav_path,
      wav: wav_path, mp3: mp3_path, midi: midi_path, provenance: provenance, log: log }
  end

  def pan_for_lane(lane, kit)
    key = { kick: "kick", snare: "snare", ghost: "snare", hats: "hat", open_hat: "openhat", ride: "ride", perc: "perc" }[lane]
    kit.dig(key, "pan").to_f
  end

  def apply_snare_verb!(mixer, events, reverb)
    level = reverb["level_drums"].to_f
    return if level <= 0

    # Snare tail: a short bright send so the backbeat sits in a room.
    snare_times = events.fetch(:drum).select { |ev| ev.lane == :snare }
    n = mixer.bus(:drums).l.length
    send = Stereo.new(n)
    snare_times.first(96).each do |ev|
      start = (ev.time * SAMPLE_RATE).round
      len = (0.12 * SAMPLE_RATE).to_i
      i = 0
      while i < len
        idx = start + i
        if idx < n
          v = NOISE[(i * 3 + 7001) % NOISE.length] * (1.0 - i.to_f / len) * ev.vel
          send.l[idx] += v
          send.r[idx] += v
        end
        i += 1
      end
    end
    tmp = Mixer.new(n.to_f / SAMPLE_RATE, catalogue.fetch("rigs").fetch("dilla_night"), Rng.new(1))
    tmp.instance_variable_set(:@buses, { melody: send, drums: mixer.bus(:drums) })
    # Reuse the plate on the send directly into the drums bus.
    plate_into!(send, mixer.bus(:drums), level)
  end

  def plate_into!(send, into, level)
    sizes = [1116, 1397].map { |s| (s * 1.1).to_i }
    ap_size = 331
    combs_l = sizes.map { |s| { buf: Array.new(s, 0.0), idx: 0 } }
    combs_r = sizes.map { |s| { buf: Array.new((s * 1.013).to_i, 0.0), idx: 0 } }
    ap_l = { buf: Array.new(ap_size, 0.0), idx: 0 }
    ap_r = { buf: Array.new(ap_size + 23, 0.0), idx: 0 }
    fb = 0.72
    n = into.l.length
    i = 0
    while i < n
      s = (send.l[i] + send.r[i]) * 0.5
      l = r = 0.0
      combs_l.each { |c| out = c[:buf][c[:idx]]; c[:buf][c[:idx]] = s + out * fb; l += out }
      combs_r.each { |c| out = c[:buf][c[:idx]]; c[:buf][c[:idx]] = s + out * fb; r += out }
      l *= 0.2
      r *= 0.2
      out_l = ap_l[:buf][ap_l[:idx]]
      ap_l[:buf][ap_l[:idx]] = l - out_l * 0.5
      l = out_l + ap_l[:buf][ap_l[:idx]] * 0.5
      out_r = ap_r[:buf][ap_r[:idx]]
      ap_r[:buf][ap_r[:idx]] = r - out_r * 0.5
      r = out_r + ap_r[:buf][ap_r[:idx]] * 0.5
      into.l[i] += l * level
      into.r[i] += r * level
      combs_l.each { |c| c[:idx] += 1; c[:idx] = 0 if c[:idx] >= c[:buf].length }
      combs_r.each { |c| c[:idx] += 1; c[:idx] = 0 if c[:idx] >= c[:buf].length }
      ap_l[:idx] += 1; ap_l[:idx] = 0 if ap_l[:idx] >= ap_l[:buf].length
      ap_r[:idx] += 1; ap_r[:idx] = 0 if ap_r[:idx] >= ap_r[:buf].length
      i += 1
    end
  end

  def encode_mp3(wav_path, mp3_path)
    return [false, nil] if which("ffmpeg").nil?

    _out, err, status = Open3.capture3("ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                                       "-i", wav_path, "-codec:a", "libmp3lame", "-b:a", "192k", mp3_path)
    [status.success?, err]
  end

  def which(binary)
    ENV["PATH"].split(File::PATH_SEPARATOR).each do |dir|
      candidate = File.join(dir, binary)
      return candidate if File.file?(candidate) && File.executable?(candidate)
    end
    nil
  end

  def render_video(opts, wav_path)
    return unless which("ffmpeg")

    mp4 = "#{wav_path.sub(/\.wav\z/, '')}.mp4"
    system("ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
           "-i", wav_path, "-filter_complex",
           "[0:a]showwaves=s=1280x360:mode=cline:colors=cyan|magenta[v];" \
           "[0:a]showcqt=s=1280x360:fps=20[cq];[v][cq]vstack[out]",
           "-map", "[out]", "-map", "0:a", "-c:v", "libx264", "-preset", "veryfast",
           "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-shortest", mp4)
    puts "dilla: video -> #{mp4}" if File.file?(mp4)
  end
end

module Dilla
  module_function

  def apply_sample_flip!(mixer, opts, groove, plan)
    source = opts.sample_loop || ENV["SAMPLE_LOOP"]
    return nil if source.to_s.strip.empty?
    unless File.file?(File.expand_path(source))
      warn "dilla sample-flip: source not found: #{source}"
      return nil
    end

    vol = (opts.sample_vol || ENV["SAMPLE_LOOP_VOL"] || SampleFlip::DEFAULT_VOL).to_f.clamp(0.0, 1.5)
    weight = (opts.sample_weight || ENV["SAMPLE_LOOP_WEIGHT"] || SampleFlip::DEFAULT_WEIGHT).to_f.clamp(0.0, 1.0)
    slices = (opts.sample_slices || SampleFlip::DEFAULT_SLICES).to_i.clamp(2, 16)

    samples = SampleFlip.decode(File.expand_path(source))
    return nil if samples.nil? || samples.length < SAMPLE_RATE

    slice_data = SampleFlip.slices_for(samples, slices)
    theory_keys = theory.fetch("keys")
    chord_slots = plan[:progression]["chords"].map do |sym|
      parsed = ChordParser.parse(sym, theory)
      pcs = [parsed[:root]] + parsed[:intervals].map { |iv| (parsed[:root] + iv) % 12 }
      pcs.uniq
    end
    chop_plan = SampleFlip.plan_chops(slice_data, chord_slots)
    crusher = DrumKit.new(catalogue.fetch("kits").fetch(plan[:kit]))

    chop_len = (slice_data.first[:length] * 0.5).to_i
    plan[:progression]["chords"].each_with_index do |_sym, idx|
      chop = chop_plan[idx % chop_plan.length]
      start_sample = (idx * (4.0 / plan[:progression]["chords"].length) * groove.bar_s * SAMPLE_RATE).round
      seg = samples[chop[:start], chop_len].dup
      next if seg.nil? || seg.length < 1024

      crusher.one_pole_lp!(seg, 6200.0)
      crusher.crush!(seg, 12)
      gain = vol * (0.7 + weight * 0.5)
      mixer.bus(:sample).add_mono!(start_sample, seg, gain * 0.95, gain)
    end
    mixer.set_gain(:sample, weight)
    { source: File.expand_path(source), slices: slices, vol: vol, weight: weight,
      picked: chop_plan.map { |c| c[:index] } }
  end

  # ------------------------------------------------------------- sidecars

  def write_quality(base, mix, lufs, stem_shares, duration, plan)
    peak = 0.0
    sum = 0.0
    n = mix.l.length
    i = 0
    while i < n
      v = (mix.l[i] + mix.r[i]) * 0.5
      a = v.abs
      peak = a if a > peak
      sum += v * v
      i += 4
    end
    rms = Math.sqrt(sum / [n / 4, 1].max)
    total = stem_shares.values.sum
    shares = stem_shares.transform_values { |v| total.positive? ? (v / total).round(3) : 0.0 }
    data = {
      "engine" => "dilla #{VERSION}", "duration_s" => duration.round(2),
      "peak_dbfs" => (20.0 * Math.log10(peak.clamp(1e-9, 1.0))).round(2),
      "rms_dbfs" => (20.0 * Math.log10(rms.clamp(1e-9, 1.0))).round(2),
      "crest_db" => (20.0 * Math.log10([peak, 1e-9].max / rms.clamp(1e-9, 1.0))).round(2),
      "lufs_estimate" => lufs.round(1),
      "stem_energy_share" => shares,
      "sonitex" => plan[:sonitex], "swing" => plan[:swing]
    }
    Dilla.atomic_write("#{base}.quality.json", JSON.pretty_generate(data))
    data
  end

  def write_session(base, plan, performer, events, sample_report)
    data = {
      "engine" => "dilla #{VERSION}",
      "progression" => plan[:progression].slice("id", "title", "key", "bpm", "loop_bars", "chords"),
      "arrangement" => plan[:arrangement],
      "drums" => plan[:drums], "groove_profile" => plan[:profile], "groove_scale" => plan[:groove_scale],
      "kit" => plan[:kit], "voice" => plan[:voice], "rig" => plan[:rig], "bars" => plan[:bars],
      "performer" => performer.slice("id", "name"),
      "event_counts" => events.transform_values(&:length),
      "sample_flip" => sample_report
    }
    Dilla.atomic_write("#{base}.session.json", JSON.pretty_generate(data))
    data
  end

  def write_provenance(base, opts, plan, performer, wav_path, session, quality)
    data = {
      "engine" => "dilla", "version" => VERSION,
      "created_at" => Time.now.utc.iso8601,
      "ruby" => RUBY_VERSION,
      "seed" => session && opts.seed ? opts.seed : (opts.seed || "random"),
      "performer" => performer["id"],
      "flags" => {
        "out" => opts.out, "progression" => opts.progression, "drums" => opts.drums,
        "midi" => opts.midi, "midi_out" => opts.midi_out, "foley" => opts.foley,
        "profile" => opts.profile, "groove" => opts.groove, "bpm" => opts.bpm, "bars" => opts.bars,
        "kit" => opts.kit, "voice" => opts.voice, "rig" => opts.rig, "sonitex" => opts.sonitex,
        "sonitex_instances" => opts.sonitex_instances, "vcs" => opts.vcs,
        "drum_balance" => opts.drum_balance, "chord_balance" => opts.chord_balance,
        "sample_loop" => opts.sample_loop || ENV["SAMPLE_LOOP"],
        "sample_vol" => opts.sample_vol || ENV["SAMPLE_LOOP_VOL"],
        "sample_weight" => opts.sample_weight || ENV["SAMPLE_LOOP_WEIGHT"],
        "sample_slices" => opts.sample_slices
      },
      "render" => {
        "wav" => wav_path, "duration_s" => quality["duration_s"], "lufs" => quality["lufs_estimate"],
        "bytes" => File.size(wav_path), "sha256" => Digest::SHA256.file(wav_path).hexdigest
      }
    }
    Dilla.atomic_write("#{base}.provenance.json", JSON.pretty_generate(data))
    data
  end
end

module Dilla
  module_function

  URL_RE = %r{https?://}i.freeze

  # ------------------------------------------------------------- reference

  # Learns from a rights-cleared recording. Source acquisition is optional;
  # the spectral measurement itself is Ruby + standard library and mix-only.
  # Stem separation was removed from the runtime rather than keeping a hidden
  # Python/Demucs dependency in a supposedly Ruby-only Studio.
  def reference(opts)
    source = opts.source
    style = %w[j_dilla industrial_techno general].include?(opts.style) ? opts.style : "j_dilla"
    require_relative File.join("..", "output_paths")
    root = Studio::OutputPaths.reference_root
    stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
    workspace = File.join(root, "analysis-#{stamp}")
    FileUtils.mkdir_p(File.join(workspace, "source"))

    wav, meta = acquire_audio(source, workspace, opts)
    return unless wav

    warn "dilla reference: using bounded, dependency-free Ruby mix analysis"
    warn "dilla reference: --no-stems is retained for compatibility; stem separation is not run" if opts.no_stems

    features_path = File.join(workspace, "features.json")
    ok = run_analyzer(wav, nil, features_path, opts)
    abort "dilla reference: analyzer failed" unless ok

    features = JSON.parse(File.read(features_path))
    profile = build_profile(features, meta, style, wav, nil)
    profile_dir = File.join(root, "profiles", style)
    FileUtils.mkdir_p(profile_dir)
    profile_path = File.join(profile_dir, "latest_profile.json")
    Dilla.atomic_write(profile_path, JSON.pretty_generate(profile))
    Dilla.atomic_write(File.join(root, "active_style.json"), JSON.generate("style_key" => style, "updated_at" => Time.now.utc.iso8601))
    Dilla.atomic_write(File.join(profile_dir, "features.json"), File.binread(features_path), binary: true)

    f = profile["features"]
    puts format("reference %s: %s - %.1f BPM (conf %.2f), key %s, density %.1f/bar, offbeat %.2f, spread %.1f ms, swing %.2f, drums %.0f%%, harmony %.0f%%; profile -> %s",
                style, meta["title"], profile["target_bpm"], f["bpm_confidence"], profile.dig("analysis", "key"),
                f["onset_density_per_bar"], f["offbeat_onset_share"], f["timing_spread_ms"], f["swing_ratio"],
                f["drums_energy_share"] * 100, f["other_energy_share"] * 100, profile_path)
  end

  def acquire_audio(source, workspace, opts)
    if source.match?(URL_RE)
      ytdlp = find_ytdlp or abort "dilla reference: yt-dlp executable is not installed"
      ffmpeg = which("ffmpeg") or abort "dilla reference: ffmpeg executable is required for URL acquisition"
      title = nil
      begin
        title_out, _title_err, status = Studio::Subprocess.capture3(
          ytdlp, "--no-playlist", "--print", "title", source, timeout: 30
        )
        title = title_out.lines.reject { |line| line.strip.empty? }.first.to_s.strip if status.success?
      rescue StandardError
        nil
      end

      out_template = File.join(workspace, "source", "reference.%(ext)s")
      cmd = [ytdlp, "--no-playlist", "-f", "bestaudio", "-x", "--audio-format", "wav",
             "--ffmpeg-location", ffmpeg, "-o", out_template]
      # Authentication remains operator-supplied; cookies are never read from
      # guessed browser profiles or included in logs.
      cookies = ENV["DILLA_YT_COOKIES"].to_s.strip
      browser = ENV["DILLA_YT_BROWSER"].to_s.strip
      cmd.concat(["--cookies", cookies]) unless cookies.empty?
      cmd.concat(["--cookies-from-browser", browser]) unless browser.empty?
      target_duration = opts.max_duration && opts.max_duration.to_f.positive? ? opts.max_duration.to_f : Studio::DillaReference::Analyzer::MAX_SECONDS
      cmd.concat(["--download-sections", "*0-#{target_duration.ceil}", "--force-keyframes-at-cuts"])
      cmd << source
      warn "dilla reference: pulling source through yt-dlp"
      out, err, status = Studio::Subprocess.capture3(*cmd, timeout: 900)
      abort "dilla reference: yt-dlp failed:\n#{err.lines.last(6).join.strip}\n#{out.lines.last(2).join.strip}" unless status.success?
      wav = Dir[File.join(workspace, "source", "reference.*")].find { |candidate| candidate.end_with?(".wav") }
      abort "dilla reference: yt-dlp produced no WAV" unless wav
      [wav, { "title" => (title && !title.empty? ? title : File.basename(source)), "url" => source }]
    else
      path = File.expand_path(source)
      abort "dilla reference: no such audio file: #{source}" unless File.file?(path)
      ffmpeg = which("ffmpeg") or abort "dilla reference: ffmpeg is required to decode this source"
      wav = File.join(workspace, "source", "reference.wav")
      temporary = File.join(workspace, "source", ".reference-#{Process.pid}.tmp.wav")
      target_duration = opts.max_duration && opts.max_duration.to_f.positive? ? opts.max_duration.to_f : Studio::DillaReference::Analyzer::MAX_SECONDS
      command = [ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", path,
                 "-t", target_duration.to_s, "-ac", "1", "-ar", "22050", temporary]
      _out, err, status = Studio::Subprocess.capture3(*command, timeout: 300)
      abort "dilla reference: ffmpeg could not decode #{path}: #{err.lines.last(4).join.strip}" unless status.success?
      abort "dilla reference: ffmpeg produced no WAV" unless File.file?(temporary)
      File.rename(temporary, wav)
      [wav, { "title" => File.basename(path), "path" => path }]
    end
  ensure
    File.delete(temporary) if defined?(temporary) && temporary && File.file?(temporary)
  end

  def find_ytdlp
    which("yt-dlp")
  end

  def run_analyzer(wav, _stems_dir, features_path, opts)
    Studio::DillaReference::Analyzer.new.write(
      wav, features_path,
      max_duration: (opts.max_duration if opts.max_duration && opts.max_duration.to_f.positive?)
    )
    true
  rescue Studio::DillaReference::AnalysisError, SystemCallError, IOError => error
    warn "dilla reference: Ruby analyzer failed: #{error.class}: #{error.message}"
    false
  end

  # Maps measured features into the profile schema MASTER's media intent reads:
  # target_bpm, groove_profile and the feature dict drive pattern ranking,
  # pocket scaling and mix balance on the next render. Restored after the
  # Python/Demucs migration dropped the method while reference() and the
  # suite still called it.
  def build_profile(features, meta, style, wav, stems_dir)
    target_bpm = features.fetch("bpm", 90.0).to_f
    spread = features.fetch("timing_spread_ms", 8.0).to_f
    swing = features.fetch("swing_ratio", 0.5).to_f
    offbeat = features.fetch("offbeat_onset_share", 0.5).to_f
    groove_profile = if swing >= 0.565 && spread > 9.0
                       "dilla_shadow"
                     elsif swing >= 0.565
                       "late_snare"
                     elsif spread > 10.5
                       "behind_the_beat"
                     else
                       "dilla_shadow"
                     end
    {
      "style_key" => style,
      "target_bpm" => target_bpm.round(1),
      "groove_profile" => groove_profile,
      "features" => {
        "bpm" => target_bpm.round(2),
        "bpm_confidence" => features.fetch("bpm_confidence", 0.0).to_f.round(3),
        "onset_density_per_bar" => features.fetch("onset_density_per_bar", 8.0).to_f.round(2),
        "offbeat_onset_share" => offbeat.round(3),
        "timing_spread_ms" => spread.round(2),
        "swing_ratio" => swing.round(3),
        "drums_energy_share" => features.fetch("drums_energy_share", 0.25).to_f.round(3),
        "bass_energy_share" => features.fetch("bass_energy_share", 0.2).to_f.round(3),
        "other_energy_share" => features.fetch("other_energy_share", 0.3).to_f.round(3),
        "vocal_energy_share" => features.fetch("vocal_energy_share", 0.0).to_f.round(3),
        "brightness_hz" => features.fetch("brightness_hz", 1500.0).to_f.round(1)
      },
      "analysis" => {
        "key" => features.dig("harmony", "key"),
        "chord_changes" => features.dig("harmony", "chord_changes"),
        "chords" => features.dig("harmony", "chords"),
        "melody" => features.fetch("melody", {}),
        "drum_grid" => features.fetch("drum_grid", {}),
        "sections" => features.fetch("sections", [])
      },
      "source" => {
        "title" => meta["title"], "url" => meta["url"], "path" => meta["path"],
        "wav" => wav, "stems_dir" => stems_dir, "duration_s" => features.fetch("duration_s", nil)
      },
      "engine" => { "name" => "dilla", "version" => VERSION },
      "created_at" => Time.now.utc.iso8601
    }
  end

  # ------------------------------------------------------------- industrial techno

  def render_industrial_techno(opts)
    opts.bpm = (opts.bpm || 132).to_f.clamp(60.0, 240.0)
    opts.bars = (opts.bars || 16).to_i.clamp(1, 128)
    seed = opts.seed
    rng = Rng.new(seed)
    srand(rng.seed)
    performer = catalogue.fetch("performers").first
    profile = { "spread_ms" => 2.0, "nudge" => { "kick" => 0.0, "snare" => 0.0, "hat" => 0.0, "ghost" => 0.0 }, "drag_ms" => 0.0, "anticipation" => 0.0 }
    groove = Groove.new(bpm: opts.bpm, swing: 50.0, profile: profile, performer: performer)
    kit = catalogue.fetch("kits").fetch("kit_break")
    rig = catalogue.fetch("rigs").fetch("basement")
    duration = opts.bars.to_i * groove.bar_s + 2.5
    mixer = Mixer.new(duration, rig, rng)
    drum_kit = DrumKit.new(kit)
    n_bars = opts.bars
    events = []
    n_bars.times do |bar|
      [[0, 1.0], [4, 1.0], [8, 1.0], [12, 1.0]].each do |step, vel|
        events << Event.new(bar * groove.bar_s + step * groove.sixteenth_s, 0.0, :kick, nil, vel, nil)
      end
      [[2, 0.7], [6, 0.7], [10, 0.7], [14, 0.75]].each { |s, v| events << Event.new(bar * groove.bar_s + s * groove.sixteenth_s, 0.0, :open_hat, nil, v, nil) }
      [[4, 0.9], [12, 0.95]].each { |s, v| events << Event.new(bar * groove.bar_s + s * groove.sixteenth_s, 0.0, :snare, nil, v, nil) }
      events << Event.new(bar * groove.bar_s, 0.5, :bass, 33 + (bar.even? ? 3 : 10), 0.8, nil)
    end
    events.each do |ev|
      samples = case ev.lane
                when :kick then drum_kit.kick(ev.vel)
                when :snare then drum_kit.snare(ev.vel)
                when :open_hat then drum_kit.hat(ev.vel, open: true)
                when :bass then Instruments.new(kit, catalogue.fetch("voices").fetch("tape_strings"), theory).bass(ev.midi, ev.vel, ev.dur)
                else next
                end
      mixer.bus(ev.lane == :bass ? :bass : :drums).add_mono!((ev.time * SAMPLE_RATE).round, samples, 0.95, 0.95)
    end
    kick_events = events.select { |e| e.lane == :kick }
    kick_events.each do |ev|
      mixer.bus(:sub).add_mono!((ev.time * SAMPLE_RATE).round, drum_kit.sub(ev.vel), 0.9, 0.9)
    end
    mixer.render_vinyl(0.3)
    mix = mixer.mixdown
    Master.dc_block!(mix)
    Master.tilt!(mix, 0.6)
    Master.saturate!(mix, 1.12)
    Sonitex.apply!(mix, "subtle", 1, rng)
    Master.normalize!(mix)
    Master.fades!(mix)
    out_base = opts.out ? File.expand_path(opts.out) : File.join(ENGINE_ROOT, "industrial-techno")
    out_base = out_base.sub(/\.(wav|mp3)\z/, "")
    FileUtils.mkdir_p(File.dirname(out_base))
    wav_path = "#{out_base}.wav"
    Wav.write_16bit(wav_path, mix)
    lufs = Master.lufs_estimate(mix)
    write_quality(out_base, mix, lufs, { "drums" => mixer.rms(:drums), "sub" => mixer.rms(:sub), "bass" => mixer.rms(:bass) }, duration, { sonitex: "subtle", swing: 50.0 })
    puts format("dilla industrial-techno: %.1f BPM, %d bars, seed %s -> %s (%.1f LUFS)", opts.bpm.to_f, n_bars, rng.seed, wav_path, lufs)
  end
end

# ---------------------------------------------------------------- entry point

Dilla.run(ARGV) if $PROGRAM_NAME == __FILE__
