# frozen_string_literal: true

require "abstract_command"
require_relative "../lib/brew_dev_tools"

module Homebrew
  module Cmd
    class Wwdd < AbstractCommand
      cmd_args do
        description <<~EOS
          Run formula PR checks that complement `brew lgtm`.
        EOS
        switch "--online",
               description: "Pass --online through to brew audit."
        flag "--base=",
             description: "Override the base branch ref used to compute changed formulae."
        named_args :formula
      end

      def run
        repo = BrewDevTools::GitRepo.new(path: Dir.pwd)
        BrewDevTools::Wwdd.new(
          repo: repo,
          stdout: $stdout,
          options: {
            online: args.online?,
            base_ref: args.base,
            formulas: args.named.to_a.map(&:to_s),
          },
        ).run
      rescue BrewDevTools::Error => e
        odie e.message
      end
    end
  end
end
