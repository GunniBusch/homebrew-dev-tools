# frozen_string_literal: true

require "abstract_command"
require_relative "../lib/brew_dev_tools"

module Homebrew
  module Cmd
    class Prsync < AbstractCommand
      cmd_args do
        description <<~EOS
          Analyze or rewrite the current tap branch so there is one commit per changed formula.
        EOS
        switch "--apply",
               description: "Rewrite the current branch from its merge-base."
        switch "--push",
               description: "Push the rewritten branch with --force-with-lease."
        switch "--pr",
               description: "Create or update the GitHub pull request after rewriting."
        flag "--message=",
             description: "Override the generated commit subject for a single formula rewrite."
        flag "--base=",
             description: "Override the base branch ref used to compute the merge-base."
        named_args :formula
      end

      def run
        repo = BrewDevTools::GitRepo.new(path: Dir.pwd)
        BrewDevTools::Prsync.new(
          repo: repo,
          stdout: $stdout,
          options: {
            apply: args.apply?,
            push: args.push?,
            pr: args.pr?,
            message: args.message,
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
