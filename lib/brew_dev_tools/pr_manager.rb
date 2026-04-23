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
      head_reference = pr_head_reference(plan.branch)

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
          "--head", head_reference,
          chdir: @repo.path,
        )
      end
    end

    private

    def current_pr(branch)
      head_reference = pr_head_reference(branch)
      result = @shell.run!(
        "gh", "pr", "view", head_reference, "--json", "number,title,url,state",
        chdir: @repo.path,
        allow_failure: true,
      )
      return nil unless result.success?

      pr = JSON.parse(result.stdout)
      return nil unless pr.fetch("state") == "OPEN"

      pr
    end

    def pr_head_reference(branch)
      head_owner = @repo.head_owner_for_branch(branch)
      return branch if head_owner.nil? || head_owner.empty?

      "#{head_owner}:#{branch}"
    end

    def pr_title(plan)
      if plan.formulas.one?
        plan.formulas.first.subject
      elsif plan.message_style == :conventional
        conventional_pr_title(plan)
      else
        first = plan.formulas.first.formula
        "#{first} and #{plan.formulas.length - 1} more formula updates"
      end
    end

    def pr_body(plan)
      validation = ValidationStore.load(repo: @repo)
      ai_disclosure = ai_disclosure(plan: plan, validation: validation)
      if @repo.homebrew_core?
        filled_template = fill_homebrew_core_template(@repo.pull_request_template, validation, ai_disclosure[:enabled])
        [
          filled_template,
          ai_disclosure[:body],
          "",
          "## Planned commits",
          *plan.formulas.map { |formula_plan| "- `#{formula_plan.subject}`" },
          "",
          "## Validation summary",
          validation_summary(validation),
        ].reject(&:empty?).join("\n")
      else
        [
          "## Changed formulae",
          *plan.formulas.map { |formula_plan| "- `#{formula_plan.formula}` via `#{formula_plan.subject}`" },
          "",
          ("## AI disclosure\n#{ai_disclosure[:body]}\n" if ai_disclosure[:enabled] && !ai_disclosure[:body].empty?),
          "## Validation summary",
          validation_summary(validation),
        ].compact.join("\n")
      end
    end

    def fill_homebrew_core_template(template, validation, ai_enabled)
      template ||= <<~TEMPLATE
        -----
        - [ ] Have you followed the guidelines for contributing?
        - [ ] Have you ensured that your commits follow the commit style guide?
        - [ ] Have you checked that there aren't other open pull requests for the same formula update/change?
        - [ ] Have you built your formula locally?
        - [ ] Is your test running fine?
        - [ ] Does your build pass brew audit?
        -----
        - [ ] AI was used to generate or assist with generating this PR. *Please specify below how you used AI to help you, and what steps you have taken to manually verify the changes*.
        -----
      TEMPLATE

      checks = {
        "commits follow the" => true,
        "built your formula locally" => validation_step_passed?(validation, "install"),
        "test running fine" => validation_step_passed?(validation, "test"),
        "build pass `brew audit" => validation_step_passed?(validation, "audit"),
        "AI was used to generate or assist" => ai_enabled,
      }

      template.lines.map do |line|
        replacement = checks.find { |needle, passed| passed && line.include?(needle) }
        replacement ? line.sub("- [ ]", "- [x]") : line
      end.join
    end

    def ai_disclosure(plan:, validation:)
      return { enabled: false, body: "" } unless plan.ai

      ai = validation && validation["ai"].is_a?(Hash) ? validation["ai"] : {}
      tool = ai["tool"] || "AI tooling"
      detail = ai["detail"] || "AI assistance was used while preparing this change."
      {
        enabled: true,
        body: [
          "AI/LLM usage: #{tool}.",
          detail,
          "I manually reviewed the generated changes and can address follow-up review feedback myself.",
        ].join(" "),
      }
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

    def conventional_pr_title(plan)
      kinds = plan.formulas.map(&:subject_kind).uniq
      prefix = if kinds == [:new_formula]
        "feat"
      elsif kinds == [:formula_fix]
        "fix"
      else
        "chore"
      end

      "#{prefix}: update #{plan.formulas.length} formula#{plan.formulas.length == 1 ? '' : 'e'}"
    end
  end
end
