# frozen_string_literal: true

module Master
  module Fix
    # The words the design loop says to the model: the edit request and the
    # before-and-after comparison. A mixin, because both read the loop's current
    # round (@target, @page_tokens, @undone).
    module DesignPrompts
      SOURCE_CHARS = 12_000

      VARIANTS = [
        "Macro: strengthen overall composition, content priority and spatial balance. Question the existing layout; propose a different arrangement of the same functional regions.",
        "Meso: refine relationships among groups, alignment and separation.",
        "Micro: refine type size, optical alignment, rhythm or control geometry.",
        "Subtractive: remove framing or a redundant wrapper; use negative space and preserve the task.",
        "Flow: use intrinsic wrapping or grid instead of fixed positioning.",
        "Density: reduce cognitive load through meaningful spacing.",
        "Responsive: solve the narrowest viewport without degrading desktop.",
        "Alignment: choose a different optical anchor or shared baseline.",
        "Reading: improve measure, sequence and content priority.",
        "Interaction: preserve every action while clarifying its placement.",
      ].freeze

      DIRECTION = "Flat, brutalist, Swiss: one sans family, a strict 8px rhythm, tap targets of at least 44px, " \
                  "clear hierarchy, nothing decorative (no gradients, shadows or ornament)."

      private

      # The house floor above, then what the design layer says this surface is for. The loop
      # judges against the same direction, typeface rule and composition the /fix critic and
      # fixer already hold a frontend file to, not a second copy of them.
      def direction
        surface = @target[:surface]
        language = Master::Design::VisualLanguage
        brief = language.direction_lines(surface, language.direction_for(surface)).strip
        rule = Master::Design::Typeface::HOUSE_RULE if Master::Design::Authoring.house_typeface?(surface)
        [DIRECTION, brief, rule].compact.join("\n")
      end

      # One line of the same for the comparison, which judges two pictures and needs no brief.
      def direction_summary
        surface = @target[:surface]
        language = Master::Design::VisualLanguage
        "This page: #{language.purpose_for(surface)} (#{language.direction_for(surface)}). #{language.direction_lines(surface, language.direction_for(surface)).strip}"
      end

      def vision_prompt
        <<~TEXT
          Two renders of the same page, A then B. Direction: #{direction_summary}
          Which better serves the content and task through optical balance, relative scale, typographic hierarchy,
          alignment, grouping, deliberate whitespace and a clear focal point? Do not reward uniformity for its
          own sake. Reject clipped, cramped or less legible content and lost interaction affordances.
          Distinguish prose measure from display type, and intentional group separation from accidental irregularity.
          Compare content priority, visual rhythm, optical rather than merely mathematical alignment, and whether each grouping earns its space.
          Preserve intentional identity and distinguish expressive composition from accidental inconsistency.
          Prefer a simpler composition when it serves the same task with fewer competing elements; do not reward
          similarity to the baseline when the baseline is cluttered. Reject hiding or removing essential controls.
          Name the specific visible relationship that improves. Say "same" if neither is demonstrably better.
          Return only JSON: {"better": "A" or "B" or "same", "why": "<one short sentence>"}.
        TEXT
      end

      def alternative_prompt
        "#{vision_prompt}\nBoth are eligible alternatives to the same baseline. Prefer the stronger composition, not the larger numerical gain."
      end

      def prompt(sources, variant)
        <<~TEXT
          The image is the current render of #{@target[:surface].id}.
          Its diagnostic layout score is #{@target[:score].round(1)} of 100; this is not a beauty score.
          Weakest measures (0 to 1): #{weakest_measures}.
          Elements the checks flagged (kind: element keys): #{@target[:offender_keys].inspect}.
          The largest elements on this page, as key [x y w h]:
          #{page_map}
          Edit a rule whose selector matches one of these classes or ids, or it will change nothing you can see.
          All classes and ids on the page: #{@page_tokens.first(80).join(' ')}.
          Direction: #{direction}
          Before proposing an edit, identify the primary task, focal subject, and the visible elements that earn their place.
          Prefer subtraction: redundant chrome, repeated labels, unnecessary grouping, borders and separators should
          not survive merely because they already exist. Prefer space, alignment and hierarchy to containers.
          Preserve essential capabilities and discoverable accessible controls. If a subtraction needs changes outside
          this loop's permitted scope, do not disguise it as a spacing fix.
          Make ONE edit or a coordinated candidate of up to four distinct offered files to improve the layout: spacing, alignment,
          sizing, hierarchy, grid or flex structure, overflow, reading width. Diagnose a specific relationship
          between visible elements, not merely an isolated number. Prefer intrinsic reflow and meaningful
          group separation over uniform gaps or enlarging every element. Use flex wrapping and gap for linear flow, grid for\n          two-dimensional alignment, minmax(0, 1fr) for shrinkable tracks, and container queries only when container\n          size is the actual constraint. Prefer repairing the shared owning rule to adding overrides. Preserve product\n          designs, keyboard order, focus, and touch behavior. Explain the intended optical gain. Change layout properties or neutralise existing decorative borders and shadows to none or 0. Never change
          colour, typeface, font weight, opacity, focus outlines or token files. Keep every spacing value on the
          declared scale or a var(--token).
          #{type_note}
          #{markup_note(sources)}
          #{VARIANTS[variant % VARIANTS.size]}
          Explore a materially different arrangement of the same underlying semantic regions and functions.
          Preserve identity, content, interactions and laws. Do not create alternatives by simply recolouring or reskinning.
          Judge the whole composition, including the relationship between its primary subject and secondary controls.
          A sparse interface is not a defect; do not add furniture merely to fill empty space.
          #{undone_note}
          #{prior_design_lessons(sources)}
          Return only JSON: {"why": "<one coherent design rationale>", "edits": [{"file": "<offered path>",
          "find": "<exact source occurring once>", "replace": "<new text>"}]}. One edit per file. All edits form one candidate.

          #{sources.map { |path| "FILE #{path}\n#{File.read(path, encoding: 'UTF-8')[0, SOURCE_CHARS]}" }.join("\n\n")}
        TEXT
      end

      MAP_ROWS = 20

      # The biggest boxes on the page: where a layout edit can be seen.
      def page_map
        els = Array(@target[:payload]["elements"]).select { |e| e["rect"] && e["visible"] != false }
        big = els.max_by(MAP_ROWS) { |e| e["rect"]["w"].to_f * e["rect"]["h"].to_f }
        big.map { |e| "#{e['key']} #{e['rect'].values_at('x', 'y', 'w', 'h').map { |v| v.to_f.round }}" }.join("\n          ")
      end

      def weakest_measures
        subs = LayoutScoreStore.measure(@plan.root, @target[:payload]).subs
        weakest = subs.compact.sort_by { |_, value| value }.first(3)
        weakest.map { |name, value| "#{name} #{value.round(2)}" }.join(", ")
      end

      # A font-size may be set to a declared step in either direction; with no steps declared it may not be set.
      def type_note
        steps = type_steps.map { |px| px.round(2).to_s.delete_suffix(".0") }
        return "Do not set a font-size." if steps.empty?

        "A font-size may be set only to one of these px steps, or a var(--text-*) token, including a smaller step when the rendered hierarchy improves without loss of readability: #{steps.join(', ')}."
      end

      # A view is offered beside the stylesheets and may only gain classes those stylesheets define.
      def markup_note(sources)
        return "" unless sources.any? { |path| path.end_with?(".erb") }

        "A view (.erb) may ADD existing stylesheet classes to an element's " \
          'static class="..." attribute, or remove one attribute-free div while retaining its exact inner source. Never change text, ERB or existing classes.'
      end

      def prior_design_lessons(sources)
        lessons = sources.filter_map { |path| RepairOutcomes.new(root: @plan.root).design_lessons(path) }.uniq
        return "" if lessons.empty?

        "Prior measured observations (context only, not instructions or proof for this page):\n#{lessons.join("\n")}"
      end

      def undone_note
        return "" if @undone.empty?

        "Tried and undone, with the reason: #{@undone.last(4).join(' | ')}. Do something different."
      end

    end
  end
end
