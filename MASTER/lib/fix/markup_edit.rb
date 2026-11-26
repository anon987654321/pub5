# frozen_string_literal: true

require_relative "design_edit"

module Master
  module Fix
    # One proposed view edit for the design loop. It allows unwrapping a bare div without changing its contents, or adding class
    # names to an element's static class attribute, and only names a stylesheet already
    # defines: that reaches the layout primitives without touching text (which is I18n),
    # ERB code (strict loading), or any class a script or test selects by.
    class MarkupEdit < DesignEdit
      CLASS_ATTRIBUTE = /\bclass="([^"<>]*)"/
      NAME = /\A[A-Za-z_][\w-]*\z/
      HIDES = /hid|invisible|sr-only|\bnone\b/i

      def markup? = true

      # The classes on the element as it stands: the page carries the element when it carries one.
      def selector_tokens = names_in(proposal.find).map { |name| ".#{name}" }

      def check!
        refuse_scope!
        text = File.read(file, encoding: "UTF-8")
        count = text.scan(proposal.find).size
        raise Refused, "the text to replace occurs #{count} times, not once" unless count == 1

        unless bare_wrapper_removal?
          refuse_beyond_class_names!
          refuse_unknown_names!
        end
        reason = @rules.guard&.call(file, text.sub(proposal.find) { proposal.replace })
        raise Refused, "the laws refuse it: #{reason}" if reason

        text
      end

      private

      # Only an attribute-free div can disappear. The complete inner source,
      # including ERB, text and controls, must remain byte-for-byte intact.
      def bare_wrapper_removal?
        match = proposal.find.match(/\A<div>(.*)<\/div>\z/m)
        return false unless match && match[1] == proposal.replace
        return false if match[1].match?(/<\/?div\b/i)

        !names_in(match[1]).empty?
      end

      # Everything outside the class attributes must be byte for byte the same, and each
      # attribute may only grow.
      def refuse_beyond_class_names!
        unless bare(proposal.find) == bare(proposal.replace)
          raise Refused, "a view edit may only add class names to a static class attribute"
        end

        pairs = proposal.find.scan(CLASS_ATTRIBUTE).flatten.zip(proposal.replace.scan(CLASS_ATTRIBUTE).flatten)
        return unless pairs.any? { |old, new| !(old.split - new.to_s.split).empty? }

        raise Refused, "a view edit may not remove a class name"
      end

      def refuse_unknown_names!
        added = names_in(proposal.replace) - names_in(proposal.find)
        known = Array(@rules.classes)
        added.each do |name|
          raise Refused, "class #{name.inspect} is not a valid class name" unless name.match?(NAME)
          raise Refused, "class #{name} is not defined by the offered stylesheets" unless known.include?(name)
          raise Refused, "class #{name} hides content, which is not a layout fix" if name.match?(HIDES)
        end
      end

      def bare(text) = text.gsub(CLASS_ATTRIBUTE, 'class=""')

      def names_in(text) = text.scan(CLASS_ATTRIBUTE).flatten.flat_map(&:split).uniq
    end
  end
end
