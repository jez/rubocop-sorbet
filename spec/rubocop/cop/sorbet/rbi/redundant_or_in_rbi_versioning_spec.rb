# frozen_string_literal: true

RSpec.describe(RuboCop::Cop::Sorbet::RedundantOrInRbiVersioning, :config) do
  it "registers an offense when RBI version annotations include a redundant or" do
    expect_offense(<<~RBI)
      # @version > 0.3.4
      # @version > 0.3.5
      ^^^^^^^^^^^^^^^^^^ Multi-line version annotations should not contain overlapping versions
      def foo; end
    RBI
  end
end
