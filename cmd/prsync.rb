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
        switch "--ai",
               description: "Force AI-assisted PR disclosure even if no detected `brew wwdd` AI report is present."
        comma_array "--closes",
                    description: "Comma-separated issues or PRs to add as `Closes ...` footer lines in the PR body. Requires `--pr`."
        comma_array "--fixes",
                    description: "Comma-separated issues or PRs to add as `Fixes ...` footer lines in the PR body. Requires `--pr`."
        comma_array "--ref",
                    description: "Comma-separated issues or PRs to add as `References ...` footer lines in the PR body. Requires `--pr`."
        flag "--message=",
             description: "Override the generated commit subject for a single formula rewrite."
        flag "--style=",
             description: "Commit/PR title style: auto, homebrew (`foo 1.2.3`), or conventional (`chore(foo): update to 1.2.3`)."
        flag "--base=",
             description: "Override the base branch ref used to compute the merge-base. By default prsync prefers the upstream/non-fork remote."
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
            ai: args.ai?,
            closes: args.closes || [],
            fixes: args.fixes || [],
            references: args.ref || [],
            message: args.message,
            message_style: args.style&.to_sym || :auto,
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
