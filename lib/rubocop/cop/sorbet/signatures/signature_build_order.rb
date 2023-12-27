# frozen_string_literal: true

begin
  require "unparser"
rescue LoadError
  nil
end

module RuboCop
  module Cop
    module Sorbet
      # Checks for the correct order of `sig` builder methods.
      #
      # Options:
      #
      # * `Order`: The order in which to enforce the builder methods are called.
      #
      # @example
      #   # bad
      #   sig { void.abstract }
      #
      #   # good
      #   sig { abstract.void }
      #
      #  # bad
      #  sig { returns(Integer).params(x: Integer) }
      #
      #  # good
      #  sig { params(x: Integer).returns(Integer) }
      class SignatureBuildOrder < ::RuboCop::Cop::Cop # rubocop:todo InternalAffairs/InheritDeprecatedCopClass
        include SignatureHelp

        # @!method root_call(node)
        def_node_search(:root_call, <<~PATTERN)
          (send nil? #builder? ...)
        PATTERN

        def on_signature(node)
          calls = call_chain(node.children[2]).map(&:method_name)
          return if calls.empty?

          expected_order = calls.sort_by do |call|
            builder_method_indexes.fetch(call) do
              # Abort if we don't have a configured order for this call,
              # likely because the method name is still being typed.
              return nil
            end
          end
          return if expected_order == calls

          message = "Sig builders must be invoked in the following order: #{expected_order.join(", ")}."

          unless can_autocorrect?
            message += " For autocorrection, add the `unparser` gem to your project."
          end

          add_offense(
            node.children[2],
            message: message,
          )
          node
        end

        def autocorrect(node)
          return unless can_autocorrect?

          lambda do |corrector|
            tree = call_chain(node_reparsed_with_modern_features(node))
              .sort_by { |call| builder_method_indexes[call.method_name] }
              .reduce(nil) do |receiver, caller|
                caller.updated(nil, [receiver] + caller.children.drop(1))
              end

            corrector.replace(
              node,
              Unparser.unparse(tree),
            )
          end
        end

        # Create a subclass of AST Builder that has modern features turned on
        class ModernBuilder < RuboCop::AST::Builder
          modernize
        end
        private_constant :ModernBuilder

        private

        # This method exists to reparse the current node with modern features enabled.
        # Modern features include "index send" emitting, which is necessary to unparse
        # "index sends" (i.e. `[]` calls) back to index accessors (i.e. as `foo[bar]``).
        # Otherwise, we would get the unparsed node as `foo.[](bar)`.
        def node_reparsed_with_modern_features(node)
          # Create a new parser with a modern builder class instance
          parser = Parser::CurrentRuby.new(ModernBuilder.new)
          # Create a new source buffer with the node source
          buffer = Parser::Source::Buffer.new(processed_source.path, source: node.source)
          # Re-parse the buffer
          parser.parse(buffer)
        end

        def can_autocorrect?
          defined?(::Unparser)
        end

        def call_chain(sig_child_node)
          return [] if sig_child_node.nil?

          call_node = root_call(sig_child_node).first
          return [] unless call_node

          calls = []
          while call_node != sig_child_node
            calls << call_node
            call_node = call_node.parent
          end

          calls << sig_child_node

          calls
        end

        def builder?(method_name)
          builder_method_indexes.key?(method_name)
        end

        def builder_method_indexes
          @configured_order ||= cop_config.fetch("Order").map(&:to_sym).each_with_index.to_h.freeze
        end
      end
    end
  end
end
