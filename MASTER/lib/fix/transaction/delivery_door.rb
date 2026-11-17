# frozen_string_literal: true

module Master
  module Fix
    class Transaction
      # The delivery door, re-opening the class defined in fix/transaction.rb:
      # what Delivery reads and the steps by which it changes this
      # transaction. Nothing else writes the delivery fields.
      def delivery
        @delivery ||= Delivery.new(self)
      end

      def enlisted_paths = @paths.dup
      def delivery_head_before = @delivery_head_before
      def delivery_head_after = @delivery_head_after
      def delivery_marked? = @delivery_marked == true

      # Sets the given DELIVERY_FIELDS and persists them, inside the named lifecycle
      # mutation when one is given; persist: false changes memory only.
      def update_delivery!(operation = nil, persist: true, **fields)
        unknown = fields.keys - DELIVERY_FIELDS
        raise ArgumentError, "unknown delivery field: #{unknown.join(", ")}" unless unknown.empty?

        write = lambda do
          @state = fields.fetch(:state, @state)
          @active = fields.fetch(:active, @active)
          @delivery_head_before = fields.fetch(:head_before, @delivery_head_before)
          @delivery_head_after = fields.fetch(:head_after, @delivery_head_after)
          @delivery_marked = fields.fetch(:marked, @delivery_marked)

          persist! if persist
          true
        end
        operation ? lifecycle_mutation(operation, item_count: @paths.size, &write) : write.call
      end

      def delivery_event(event, **payload) = emit(event, **payload)
    end
  end
end
