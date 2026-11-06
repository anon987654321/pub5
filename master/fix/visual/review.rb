# frozen_string_literal: true

require "json"
require "date"
require_relative "pixel_match"

module Fix
  module Visual
    # One visual change to judge: the Laws it answers to, the place, the
    # evidence the sweep measured, and the before and after shots (PNG bytes).
    Group = Data.define(:key, :law, :place, :surfaces, :evidence, :before, :after)

    # The independent reviewer (pub4 d7314bf0ec). The model that proposed a
    # visual change never approves it: a separate ask, to a different model,
    # judges it against the named Laws only, with each changed region cropped
    # and enlarged 400%, and must explain every region. Only "APPROVE" with
    # one "R<n>:" line a region approves; an unexplained region rejects.
    module Reviewer
      CROPS = 6
      DIR = "tmp/fix/visual/review"
      BRIEF = <<~TEXT
        INDEPENDENT VISUAL REVIEW
        You did not make this change and you are not asked to improve it. Judge it against the Laws
        named below and nothing else: not taste, not a look. The principles behind those Laws are the
        Swiss/International typographic style, Bringhurst on measure, scale and rhythm, and
        Mueller-Brockmann's grid systems; apply them as measurements, not as a style to imitate.

        The changed regions of the re-rendered page are cropped and enlarged 400% so edges, alignment
        and baselines read at the pixel; each is listed as R<n> x,y wxh with the file that holds it,
        followed by the findings and computed values the browser reported.
        Answer APPROVE or REJECT on the first line. After APPROVE give one line a region,
        "R<n>: <which Law this change satisfies and how>"; a region you cannot explain means REJECT.
      TEXT

      module_function

      # :approved, or why not. reviewer answers ask(brief) with a reply whose text is the verdict.
      def judge(world, group, regions, reviewer:)
        return "no independent reviewer configured" unless reviewer

        crops = crops(world, group, regions)
        verdict(reviewer.ask(brief(group, regions, crops), task: "review").text.to_s, regions)
      end

      def brief(group, regions, crops = [])
        boxes = regions.each_with_index.map { |b, i| "R#{i + 1} #{b[:x]},#{b[:y]} #{b[:w]}x#{b[:h]}#{" #{crops[i]}" if crops[i]}" }
        [BRIEF, "Laws: #{group.law}", "Changed regions:", *boxes, "Findings:", *Array(group.evidence)].join("\n")
      end

      def crops(world, group, regions)
        return [] unless group.after

        regions.first(CROPS).each_with_index.map do |box, index|
          path = File.join(DIR, "#{group.key.gsub(/\W+/, '_')}-R#{index + 1}.png")
          world.write(path, PixelMatch.crop(group.after, box))
          path
        end
      end

      def verdict(text, regions)
        first = text.lines.first.to_s.strip
        return "rejected: #{first.sub(/\AREJECT:?\s*/, '')[0, 160]}" unless first.start_with?("APPROVE")

        missing = regions.each_index.find { |i| !text.match?(/^R#{i + 1}:/) }
        missing ? "rejected: R#{missing + 1} left unexplained" : :approved
      end
    end

    # What keeps a fixed defect from coming back (pub4 d7314bf0ec). Each
    # cleared group leaves a row (finding kind, selector or stylesheet,
    # surfaces); a later finding of that kind, at that place, on one of those
    # surfaces is reported hard, "[guarded]", instead of soft.
    module Guards
      PATH = "master/fix/visual/guards.jsonl"

      module_function

      def rows(world)
        world.read(PATH).lines.filter_map { |line| JSON.parse(line) rescue nil }
      rescue Errno::ENOENT
        []
      end

      def guarded?(message, rows)
        rows.any? do |row|
          message.include?("#{row['kind']}:") && message.include?(row["place"]) &&
            Array(row["surfaces"]).any? { |surface| message.include?(surface) }
        end
      end

      def mark(messages, rows) = messages.map { |m| guarded?(m, rows) ? "#{m} [guarded]" : m }

      def record(world, kind:, place:, surfaces:)
        kept = rows(world)
        row = { "kind" => kind, "place" => place, "surfaces" => surfaces.first(3) }
        return row if kept.any? { |old| old.except("since") == row }

        text = kept.map { |old| JSON.generate(old) }.push(JSON.generate(row.merge("since" => Date.today.iso8601))).join("\n")
        world.write(PATH, "#{text}\n")
        row
      end
    end

    # Design2Code's reference comparison with the DOM instead of OCR (pub4
    # 638074a99f): two geometry walks' elements paired by role (or tag) and
    # text, in order, with each pair's position, size, type-size and colour
    # deltas. A report input for tuning toward a reference, never a gate.
    module Reference
      Pair = Data.define(:key, :ours, :theirs) do
        def deltas
          boxes = [ours, theirs].map { |el| el["frect"] || {} }
          moved = %w[x y w h].to_h { |axis| [axis, gap(*boxes.map { |b| b[axis] })] }
          colours = [ours["color"], theirs["color"]]
          moved.merge("font_size" => gap(ours["font_size"], theirs["font_size"]), "color" => colours.uniq.size > 1 ? colours : nil)
        end

        def gap(one, two) = (one.to_f - two.to_f).round(1)
        def distance = deltas.slice("x", "y", "w", "h", "font_size").values.sum(&:abs)
      end

      module_function

      def key(el)
        text = el["text"].to_s.downcase.gsub(/\s+/, " ").strip[0, 40]
        [el["role"] || el["tag"], text] unless text.empty?
      end

      def compare(ours, theirs)
        pool = Array(theirs).group_by { |el| key(el) }
        Array(ours).filter_map do |el|
          found = key(el) or next
          match = pool[found]&.shift or next
          Pair.new(key: found, ours: el, theirs: match)
        end
      end

      def report(pairs, limit: 12)
        rows = pairs.sort_by { |p| -p.distance }.first(limit).map do |pair|
          moved = pair.deltas.reject { |_, delta| delta.nil? || delta == 0.0 }
          "#{pair.key.join(' ')}: #{moved.map { |axis, delta| "#{axis} #{delta}" }.join(', ')}"
        end
        ["REFERENCE DELTAS (ours minus reference, CSS px; matched #{pairs.size})", *rows].join("\n")
      end
    end
  end
end
