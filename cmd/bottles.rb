# frozen_string_literal: true

require "abstract_command"
require_relative "../lib/brew_dev_tools"

module Homebrew
  module Cmd
    class Bottles < AbstractCommand
      cmd_args do
        description <<~EOS
          Browse stable bottle metadata, inspect bottle archive contents, or compare two bottles without installing them.
        EOS
        switch "--compare",
               description: "Compare exactly two formulae instead of listing bottle metadata."
        switch "--contents",
               description: "Inspect the contents of a specific bottle archive."
        flag "--tag=",
             description: "Bottle tag to inspect or compare, for example `arm64_sequoia`."
        switch "--urls",
               description: "Include full bottle URLs in the output."
        named_args :formula
      end

      def run
        BrewDevTools::Bottles.new(
          stdout: $stdout,
          options: {
            compare: args.compare?,
            contents: args.contents?,
            show_urls: args.urls?,
            tag: args.tag,
            formulas: args.named.to_a.map(&:to_s),
          },
        ).run
      rescue BrewDevTools::Error => e
        odie e.message
      end
    end
  end
end
