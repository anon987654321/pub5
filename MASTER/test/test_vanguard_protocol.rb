# frozen_string_literal: true

require "prism"
require_relative "test_helper"

class TestVanguardProtocol < Minitest::Test
  include Master

  def test_command_guard_rejects_banned_tokens
    assert_raises(Master::SecurityError) do
      Review::Security::CommandGuard.validate_command!(["grep", "-R", "foo", "."])
    end
  end

  def test_command_guard_secure_execute_returns_result
    result = Review::Security::CommandGuard.secure_execute(%w[echo ok])
    assert result.ok?
    assert_includes result.value!, "ok"
  end

  def test_runtime_loop_guards_allow_non_falcon_context
    assert Ops::RuntimeLoopGuards.guard_subprocess_context!
  end

  # A detector class joins a scan only when a ::Law.define names it, so this
  # fixture stays out of every scan the process runs afterwards.
  class ExplodingAstRule < Review::Scan::Detector
    def initialize
      super
      @id = "exploding_ast"
    end

    def check_ast(_ast, _code, path:)
      raise "fixture AST failure at #{path}"
    end
  end

  def test_ast_rule_failure_is_not_clean
    rule = ExplodingAstRule.new
    error = assert_raises(RuntimeError) do
      rule.check("class Broken", path: "broken.rb")
    end
    assert_match(/exploding_ast AST check failed/, error.message)
  end

  def test_symbol_visitor_qualifies_calls_by_lexical_method_context
    source = <<~RUBY
      module Demo
        class Widget
          def ping
            helper
            self.instance_reset
            Other.reset
            worker.run
          end
          def helper = true
          def instance_reset = true
          def self.reset = true
          def self.build
            class_helper
          end
          def self.class_helper = true
          class << self
            def singleton_ping
              singleton_helper
            end
            def singleton_helper = true
          end
        end
      end
    RUBY
    ast = Prism.parse(source)
    assert ast.success?, ast.errors.map(&:message).join("; ")
    visitor = Review::CodeIndex::SymbolVisitor.new(file: "calls.rb", root: Dir.pwd)
    ast.value.accept(visitor)
    targets = visitor.references.map(&:to_fqn)

    assert_includes targets, "Demo::Widget#helper"
    assert_includes targets, "Demo::Widget#instance_reset"
    assert_includes targets, "Other.reset"
    assert_includes targets, "run", "dynamic receivers remain unqualified rather than guessed"
    assert_includes targets, "Demo::Widget.class_helper"
    assert_includes targets, "Demo::Widget.singleton_helper"
  end

  def test_symbol_visitor_tracks_macro_alias_and_singleton_definitions
    source = <<~RUBY
      module Dynamic
        class Widget
          define_method(:computed) {}
          attr_reader :name, "state"
          attr_writer :setting
          attr_accessor :enabled
          alias renamed computed
          alias_method :renamed_again, "computed"
          def self.build = true
          class << self
            def from_singleton_class = true
            define_method(:singleton_dynamic) {}
            attr_reader :singleton_name
          end
        end
      end
    RUBY
    ast = Prism.parse(source)
    assert ast.success?, ast.errors.map(&:message).join("; ")
    visitor = Review::CodeIndex::SymbolVisitor.new(file: "dynamic.rb", root: Dir.pwd)
    ast.value.accept(visitor)
    names = visitor.symbols.map(&:fqn)

    %w[
      Dynamic::Widget#computed
      Dynamic::Widget#name
      Dynamic::Widget#state
      Dynamic::Widget#setting=
      Dynamic::Widget#enabled
      Dynamic::Widget#enabled=
      Dynamic::Widget#renamed
      Dynamic::Widget#renamed_again
      Dynamic::Widget.build
      Dynamic::Widget.from_singleton_class
      Dynamic::Widget.singleton_dynamic
      Dynamic::Widget.singleton_name
    ].each { |name| assert_includes names, name }

    assert_equal 12, visitor.metrics[:defs]
  end

  def test_symbol_visitor_tracks_metrics
    source = <<~RUBY
      module Demo
        class Widget
          def ping = true
          def self.reset = true
        end
      end
    RUBY
    ast = Prism.parse(source).value
    visitor = Review::CodeIndex::SymbolVisitor.new(file: "demo.rb", root: Dir.pwd)
    ast.accept(visitor)
    assert_equal 1, visitor.metrics[:modules]
    assert_equal 1, visitor.metrics[:classes]
    assert_equal 2, visitor.metrics[:defs]
    names = visitor.symbols.map(&:fqn)
    assert_includes names, "Demo::Widget#ping"
    assert_includes names, "Demo::Widget.reset"
  end
end
