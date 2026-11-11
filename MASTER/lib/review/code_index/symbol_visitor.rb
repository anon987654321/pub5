# frozen_string_literal: true

require "prism"

module Master
  module Review
    class CodeIndex
      # Walks one Prism tree and collects its class, module and method symbols and call references.
      class SymbolVisitor < Prism::Visitor
        attr_reader :symbols, :references, :metrics

        def initialize(file:, root:)
          @file = file; @root = root
          @symbols = []; @references = []; @scope = []
          @method_depth = 0
          @singleton_depth = 0
          @metrics = { classes: 0, modules: 0, defs: 0 }
        end

        def visit_class_node(node)
          name = const_name(node.constant_path)
          fqn = qualified(name)
          @symbols << Symbol.new(
            fqn:,
            type: :class,
            file: @file,
            line: node.location.start_line,
            parent: node.superclass ? const_name(node.superclass) : "Object",
            includes: [],
          )
          @metrics[:classes] += 1
          @scope.push(name); super; @scope.pop
        end

        def visit_module_node(node)
          name = const_name(node.constant_path)
          fqn = qualified(name)
          @symbols << Symbol.new(
            fqn:,
            type: :module,
            file: @file,
            line: node.location.start_line,
            parent: nil,
            includes: [],
          )
          @metrics[:modules] += 1
          @scope.push(name); super; @scope.pop
        end

        def visit_def_node(node)
          separator = (node.receiver || @singleton_depth.positive?) ? "." : "#"
          add_method_symbol(node.name, node, separator:)
          @method_depth += 1
          begin
            super
          ensure
            @method_depth -= 1
          end
        end

        # class << self changes the meaning of every implicit definition in
        # its body. Keep that context explicit rather than mislabelling those
        # methods as instance methods.
        def visit_singleton_class_node(node)
          @singleton_depth += 1
          super
        ensure
          @singleton_depth -= 1
        end

        def visit_alias_method_node(node)
          separator = @singleton_depth.positive? ? "." : "#"
          add_method_symbol(node.new_name, node, separator:)
          super
        end

        def visit_call_node(node)
          record_generated_methods(node)
          method_name = node.name.to_s
          return super unless method_name.match?(/\A[_a-z][a-z0-9_]*[!?]?\z/i) && method_name.length > 1
          receiver = receiver_name(node.receiver)
          to_fqn = receiver ? "#{receiver}##{method_name}" : method_name
          @references << Reference.new(
            from_file: @file,
            from_line: node.location.start_line,
            to_fqn:,
            ref_type: :call,
          )
          super
        end

        private

        def record_generated_methods(node)
          return unless @method_depth.zero?
          return unless node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode)

          arguments = node.arguments&.arguments || []
          separator = @singleton_depth.positive? ? "." : "#"
          case node.name
          when :define_method, :alias_method
            add_method_symbol(arguments.first, node, separator:) unless arguments.empty?
          when :define_singleton_method
            add_method_symbol(arguments.first, node, separator: ".") unless arguments.empty?
          when :attr_reader, :attr
            arguments.first(node.name == :attr ? 1 : arguments.size).each do |argument|
              add_method_symbol(argument, node, separator:)
            end
            if node.name == :attr && arguments[1].is_a?(Prism::TrueNode)
              arguments.first(1).each { |argument| add_method_symbol("#{literal_method_name(argument)}=", node, separator:) }
            end
          when :attr_writer
            arguments.each do |argument|
              name = literal_method_name(argument)
              add_method_symbol("#{name}=", node, separator:) unless name.empty?
            end
          when :attr_accessor
            arguments.each do |argument|
              name = literal_method_name(argument)
              next if name.empty?

              add_method_symbol(name, node, separator:)
              add_method_symbol("#{name}=", node, separator:)
            end
          when :module_function
            arguments.each { |argument| add_method_symbol(argument, node, separator: ".") }
          end
        end

        def literal_method_name(node)
          return "" unless node
          return node.unescaped.to_s if node.respond_to?(:unescaped)

          ""
        end

        def add_method_symbol(name_node, source_node, separator:)
          name = name_node.respond_to?(:unescaped) ? name_node.unescaped.to_s : name_node.to_s
          return if name.empty? || name.match?(/[\r\n\0]/) || name.bytesize > 200

          owner = @scope.empty? ? "(top)" : @scope.join("::")
          @symbols << Symbol.new(
            fqn: "#{owner}#{separator}#{name}",
            type: :method,
            file: @file,
            line: source_node.location.start_line,
            parent: owner,
            includes: [],
          )
          @metrics[:defs] += 1
        end

        def qualified(name)
          return name if @scope.empty? || name.include?("::")
          (@scope + [name]).join("::")
        end

        def receiver_name(node)
          case node
          when Prism::SelfNode
            @scope.join("::")
          when Prism::ConstantReadNode, Prism::ConstantPathNode, Prism::ConstantPathTargetNode
            const_name_safe(node)
          else
            nil
          end
        end

        def const_name(node)
          case node
          when Prism::ConstantReadNode then node.name.to_s
          when Prism::ConstantPathNode, Prism::ConstantPathTargetNode
            "#{const_name(node.parent)}::#{node.name}"
          else node.respond_to?(:name) ? node.name.to_s : ""
          end
        end

        def const_name_safe(node)
          name = const_name(node)
          name.empty? ? nil : name
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "code_index.const_name_safe")
          nil
        end
      end
    end
  end
end
