# frozen_string_literal: true

require "stringio"
require "zlib"
require "rexml/document"
require "rexml/xpath"
require "pathname"

module Studio
  module ALS
    SCHEMA = "studio.ableton-live-set.v1"

    class ParseError < StandardError; end

    # Ableton Live Set files are normally gzip-compressed XML. The parser also
    # accepts plain XML so extracted/diagnostic files can be inspected.
    class Parser
      MAX_SOURCE_BYTES = 256 * 1024 * 1024
      TRACK_TYPES = %w[MidiTrack AudioTrack GroupTrack ReturnTrack MasterTrack].freeze
      CLIP_TYPES = %w[MidiClip AudioClip].freeze
      NOTE_TYPES = %w[MidiNoteEvent].freeze
      AUTOMATION_POINT_TYPES = %w[FloatEvent EnumEvent BoolEvent MidiCCEvent].freeze

      def parse(source)
        bytes, source_name = read_source(source)
        xml = inflate(bytes)
        raise ParseError, "Live Set XML exceeds #{MAX_SOURCE_BYTES} bytes" if xml.bytesize > MAX_SOURCE_BYTES
        if xml.match?(/<!\s*(?:DOCTYPE|ENTITY)/i)
          raise ParseError, "DTD and entity declarations are not accepted in Live Set XML"
        end

        document = REXML::Document.new(xml)
        root = document.root
        raise ParseError, "XML document has no root element" unless root

        live_set = root.name == "LiveSet" ? root : descendants(root, "LiveSet").first
        raise ParseError, "no LiveSet element found" unless live_set

        tracks_node = descendants(live_set, "Tracks").first
        tracks = track_elements(tracks_node).each_with_index.map do |element, index|
          parse_track(element, index)
        end

        {
          "schema" => SCHEMA,
          "source_file" => source_name,
          "title" => project_title(live_set, source_name),
          "ableton_version" => ableton_version(root),
          "tempo_bpm" => project_tempo(live_set),
          "time_signature" => time_signature(live_set),
          "tracks" => tracks,
          "limitations" => {
            "audio_content" => "Audio clips are represented by file references; sample bytes are not embedded in this archive.",
            "device_state" => "Native Ableton device parameters and third-party plug-in state are not reconstructed by this parser.",
            "automation" => "Supported automation event points are exported; complex device-specific automation semantics may require Live."
          }
        }
      rescue REXML::ParseException => error
        raise ParseError, "invalid Live Set XML: #{error.message}"
      rescue Zlib::Error => error
        raise ParseError, "could not decompress Live Set: #{error.message}"
      end

      private

      def read_source(source)
        if source.respond_to?(:read)
          [source.read.to_s.b, source.respond_to?(:path) ? File.basename(source.path.to_s) : "(stream)"]
        else
          path = File.expand_path(source.to_s)
          raise ParseError, "Live Set file does not exist: #{path}" unless File.file?(path)

          size = File.size(path)
          raise ParseError, "Live Set file exceeds #{MAX_SOURCE_BYTES} bytes" if size > MAX_SOURCE_BYTES
          [File.binread(path), File.basename(path)]
        end
      rescue SystemCallError => error
        raise ParseError, "could not read Live Set: #{error.message}"
      end

      def inflate(bytes)
        return bytes unless bytes.start_with?("\x1f\x8b".b)

        reader = Zlib::GzipReader.new(StringIO.new(bytes))
        output = String.new(encoding: Encoding::BINARY)
        while (chunk = reader.read(64 * 1024)) && !chunk.empty?
          output << chunk
          raise ParseError, "decompressed Live Set exceeds #{MAX_SOURCE_BYTES} bytes" if output.bytesize > MAX_SOURCE_BYTES
        end
        output
      ensure
        reader&.close
      end

      def track_elements(tracks_node)
        return [] unless tracks_node

        tracks_node.elements.to_a.select { |element| TRACK_TYPES.include?(element.name) }
      end

      def parse_track(element, index)
        clips = descendants(element).select { |child| CLIP_TYPES.include?(child.name) }
        {
          "id" => element.attributes["Id"],
          "kind" => element.name.sub(/Track\z/, "").downcase,
          "name" => track_name(element, index),
          "clips" => clips.map { |clip| parse_clip(clip) },
          "automation" => automation(element)
        }
      end

      def track_name(track, index)
        name_node = descendants(track, "Name").first
        value_node = name_node && (descendants(name_node, "UserName").first || descendants(name_node, "EffectiveName").first)
        value = value_node && node_value(value_node)
        value = node_value(name_node) if value.to_s.empty? && name_node
        value = track.attributes["Name"] if value.to_s.empty?
        value.to_s.empty? ? "#{track.name.downcase}-#{index + 1}" : value.to_s
      end

      def parse_clip(clip)
        loop_node = descendants(clip, "Loop").first
        loop_start = value_for(clip, "LoopStart")
        loop_end = value_for(clip, "LoopEnd")
        content_start = value_for(clip, "CurrentStart")
        content_end = value_for(clip, "CurrentEnd")
        start_beats = clip_position(clip)
        length_beats = numeric_attribute(clip, "Duration", "Length")
        end_value = numeric_value(content_end)
        start_value = numeric_value(content_start)
        length_beats ||= end_value - start_value if end_value && start_value
        length_beats ||= numeric_value(loop_end) - numeric_value(loop_start) if loop_end && loop_start
        name_node = descendants(clip, "Name").first
        name_value = name_node && (descendants(name_node, "UserName").first || descendants(name_node, "EffectiveName").first)
        name = name_value && node_value(name_value)
        name = node_value(name_node) if name.to_s.empty? && name_node

        result = {
          "kind" => clip.name.sub(/Clip\z/, "").downcase,
          "id" => clip.attributes["Id"],
          "name" => name.to_s.empty? ? clip.name : name,
          "start_beats" => start_beats,
          "length_beats" => length_beats,
          "content_start_beats" => numeric_value(content_start),
          "content_end_beats" => numeric_value(content_end),
          "loop_start_beats" => numeric_value(loop_start),
          "loop_end_beats" => numeric_value(loop_end),
          "loop_enabled" => boolean_value(value_for(clip, "LoopOn")),
          "notes" => clip.name == "MidiClip" ? midi_notes(clip) : [],
          "audio_references" => clip.name == "AudioClip" ? audio_references(clip) : [],
          "automation" => automation(clip)
        }
        result["loop_enabled"] = false if result["loop_enabled"].nil?
        result
      end

      def clip_position(clip)
        value = numeric_attribute(clip, "Time", "Position", "Start")
        return value unless value.nil?

        # Arrangement clips sometimes keep their position on a wrapper/event
        # parent rather than on the MidiClip or AudioClip node itself.
        parent = clip.parent
        while parent && parent.respond_to?(:attributes)
          value = numeric_attribute(parent, "Time", "Position", "Start")
          return value unless value.nil?
          parent = parent.parent
        end
        0.0
      end

      def midi_notes(clip)
        descendants(clip).select { |node| NOTE_TYPES.include?(node.name) }.map do |node|
          key_track = ancestor(node, "KeyTrack")
          key_node = key_track && descendants(key_track, "MidiKey").first
          pitch = numeric_attribute(node, "Pitch", "Key")
          pitch ||= numeric_value(node_value(key_node)) if key_node
          {
            "id" => node.attributes["NoteId"] || node.attributes["Id"],
            "pitch" => pitch&.to_i,
            "start_beats" => numeric_attribute(node, "Time", "Start") || 0.0,
            "duration_beats" => numeric_attribute(node, "Duration", "Length") || 0.0,
            "velocity" => numeric_attribute(node, "Velocity") || 0.0,
            "release_velocity" => numeric_attribute(node, "OffVelocity", "ReleaseVelocity"),
            "enabled" => boolean_value(node.attributes["IsEnabled"] || node.attributes["Enabled"]),
            "probability" => numeric_attribute(node, "Probability"),
            "velocity_deviation" => numeric_attribute(node, "VelocityDeviation")
          }
        end
      end

      def audio_references(clip)
        descendants(clip).select { |node| %w[FileRef SampleRef OriginalFileRef].include?(node.name) }.map do |node|
          {
            "kind" => node.name,
            "name" => value_for(node, "Name") || node.attributes["Name"],
            "path" => value_for(node, "Path") || value_for(node, "RelativePath") ||
                     value_for(node, "RelativePathName") || node.attributes["Path"],
            "type" => node.attributes["Type"],
            "id" => node.attributes["Id"]
          }.reject { |_key, value| value.nil? || value == "" }
        end.uniq
      end

      def automation(node)
        descendants(node, "AutomationEnvelope").map do |envelope|
          target = descendants(envelope, "AutomationTarget").first
          points = descendants(envelope).select { |child| AUTOMATION_POINT_TYPES.include?(child.name) }.map do |point|
            {
              "kind" => point.name,
              "time_beats" => numeric_attribute(point, "Time") || 0.0,
              "value" => numeric_attribute(point, "Value"),
              "curve_control1" => numeric_attribute(point, "CurveControl1"),
              "curve_control2" => numeric_attribute(point, "CurveControl2")
            }.reject { |_key, value| value.nil? }
          end
          {
            "target_id" => target && (target.attributes["Id"] || value_for(target, "Id")),
            "points" => points
          }
        end
      end

      def project_title(live_set, source_name)
        name_node = live_set.elements["Name"]
        named = if name_node
                  user_name = descendants(name_node, "UserName").first || descendants(name_node, "EffectiveName").first
                  node_value(user_name) || node_value(name_node)
                end
        value = live_set.attributes["Name"] || named
        value.to_s.empty? ? File.basename(source_name.to_s, File.extname(source_name.to_s)) : value
      end

      def ableton_version(root)
        %w[MajorVersion MinorVersion Creator SchemaChangeCount].each_with_object({}) do |key, result|
          value = root.attributes[key]
          result[key.downcase] = value if value
        end
      end

      def project_tempo(live_set)
        tempo = descendants(live_set, "Tempo").first
        return nil unless tempo

        manual = descendants(tempo, "Manual").first
        value = manual ? node_value(manual) : node_value(tempo)
        numeric_value(value)
      end

      def time_signature(live_set)
        node = descendants(live_set, "TimeSignature").first
        return nil unless node

        numerator = numeric_value(value_for(node, "Numerator"))
        denominator = numeric_value(value_for(node, "Denominator"))
        return nil unless numerator && denominator

        { "numerator" => numerator.to_i, "denominator" => denominator.to_i }
      end

      def value_for(node, name)
        child = descendants(node, name).first
        child && node_value(child)
      end

      def numeric_attribute(node, *names)
        names.each do |name|
          value = node.attributes[name]
          parsed = numeric_value(value)
          return parsed unless parsed.nil?
        end
        nil
      end

      def numeric_value(value)
        return nil if value.nil?

        Float(value)
      rescue ArgumentError, TypeError
        nil
      end

      def boolean_value(value)
        return nil if value.nil?

        %w[true 1 yes].include?(value.to_s.downcase)
      end

      def node_value(node)
        return nil unless node

        node.attributes["Value"] || node.attributes["value"] || node.text
      end

      def ancestor(node, name)
        current = node.parent
        while current
          return current if current.respond_to?(:name) && current.name == name
          current = current.parent
        end
        nil
      end

      def descendants(node, name = nil, result = [])
        return result unless node.respond_to?(:elements)

        node.elements.each do |child|
          result << child if name.nil? || child.name == name
          descendants(child, name, result)
        end
        result
      end
    end
  end
end
