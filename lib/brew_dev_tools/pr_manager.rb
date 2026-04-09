# frozen_string_literal: true

module BrewDevTools
  class PRManager
    def initialize(repo:, shell: Shell.new, stdout: $stdout)
      @repo = repo
      @shell = shell
      @stdout = stdout
    end

    def sync_pr!(plan)
      @shell.run!("gh", "auth", "status", chdir: @repo.path)

      title = pr_title(plan)
      body = pr_body(plan)
      existing_pr = current_pr(plan.branch)

      if existing_pr
        @stdout.puts("Updating PR ##{existing_pr.fetch('number')}...")
        @shell.run!(
          "gh", "pr", "edit", existing_pr.fetch("number").to_s,
          "--title", title, "--body", body,
          chdir: @repo.path,
        )
        existing_pr.fetch("number")
      else
        @stdout.puts("Creating PR...")
        @shell.run!(
          "gh", "pr", "create",
          "--title", title,
          "--body", body,
          "--base", @repo.default_branch_name,
          "--head", plan.branch,
          chdir: @repo.path,
        )
      end
    end

    private

    def current_pr(branch)
      result = @shell.run!(
        "gh", "pr", "list", "--head", branch, "--json", "number,title,url",
        chdir: @repo.path,
      )
      prs = JSON.parse(result.stdout)
      prs.first
    end

    def pr_title(plan)
      if plan.formulas.one?
        plan.formulas.first.subject
      else
        first = plan.formulas.first.formula
        "#{first} and #{plan.formulas.length - 1} more formula updates"
      end
    end

    def pr_body(plan)
      validation = ValidationStore.load(repo: @repo)
      if @repo.homebrew_core?
        filled_template = fill_homebrew_core_template(@repo.pull_request_template, validation)
        [
          filled_template,
          "",
          "## Planned commits",
          *plan.formulas.map { |formula_plan| "- `#{formula_plan.subject}`" },
          "",
          "## Validation summary",
          validation_summary(validation),
        ].join("\n")
      else
        [
          "## Changed formulae",
          *plan.formulas.map { |formula_plan| "- `#{formula_plan.formula}` via `#{formula_plan.subject}`" },
          "",
          "## Validation summary",
          validation_summary(validation),
        ].join("\n")
      end
    end

    def fill_homebrew_core_template(template, validation)
      template ||= <<~TEMPLATE
        -----
        - [ ] Have you followed the guidelines for contributing?
        - [ ] Have you ensured that your commits follow the commit style guide?
        - [ ] Have you checked that there aren't other open pull requests for the same formula update/change?
        - [ ] Have you built your formula locally?
        - [ ] Is your test running fine?
        - [ ] Does your build pass brew audit?
        -----
      TEMPLATE

      checks = {
        "commits follow the" => true,
        "built your formula locally" => validation_step_passed?(validation, "install"),
        "test running fine" => validation_step_passed?(validation, "test"),
        "build pass `brew audit" => validation_step_passed?(validation, "audit"),
      }

      template.lines.map do |line|
        replacement = checks.find { |needle, passed| passed && line.include?(needle) }
        replacement ? line.sub("- [ ]", "- [x]") : line
      end.join
    end

    def validation_summary(validation)
      return "- No `brew wwdd` report found." unless validation

      lines = validation.fetch("formulas").map do |formula_report|
        steps = formula_report.fetch("steps").map do |step|
          "#{step.fetch('name')}: #{step.fetch('success') ? 'pass' : 'fail'}"
        end
        "- `#{formula_report.fetch('formula')}`: #{steps.join(', ')}"
      end
      lines.join("\n")
    end

    def validation_step_passed?(validation, step_name)
      return false unless validation

      validation.fetch("formulas").all? do |formula_report|
        formula_report.fetch("steps").any? do |step|
          step.fetch("name") == step_name && step.fetch("success")
        end
      end
    end
  end
end
