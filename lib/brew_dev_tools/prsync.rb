# frozen_string_literal: true

module BrewDevTools
  class Prsync
    FormulaPlan = Struct.new(
      :formula,
      :path,
      :subject,
      :subject_kind,
      :generated_summary,
      :operations,
      keyword_init: true,
    )

    Plan = Struct.new(
      :branch,
      :base_ref,
      :base_sha,
      :head_sha,
      :upstream_remote,
      :backup_branch,
      :message_style,
      :formulas,
      keyword_init: true,
    )

    attr_reader :repo

    def initialize(repo:, shell: Shell.new, stdout: $stdout, options: {})
      @repo = repo
      @shell = shell
      @stdout = stdout
      @apply = options.fetch(:apply, false)
      @push = options.fetch(:push, false)
      @pr = options.fetch(:pr, false)
      @message = options[:message]
      @message_style = options.fetch(:message_style, :auto)
      @base_ref = options[:base_ref]
      @formulas = options.fetch(:formulas, [])
      @pr_manager = options[:pr_manager] || PRManager.new(repo: repo, shell: shell, stdout: stdout)
      @time_source = options[:time_source] || -> { Time.now.utc }
    end

    def run
      change_set = repo.inspect_change_set(formulas: @formulas, base_ref: @base_ref)
      plan = build_plan(change_set)
      print_preview(plan)
      return plan unless @apply

      apply_plan!(plan)
      @pr_manager.sync_pr!(plan) if @pr
      plan
    end

    def build_plan(change_set)
      resolved_style = resolve_message_style
      single_formula_override = @message && change_set.formula_states.length == 1
      formula_plans = change_set.formula_states.map do |formula_state|
        suggestion = CommitSubject.for_formula(
          formula: formula_state.formula,
          base_content: formula_state.base_content,
          final_content: formula_state.final_content,
          style: resolved_style,
        )
        subject, generated_summary = resolved_subject(
          formula_state: formula_state,
          suggestion: suggestion,
          single_formula_override: single_formula_override,
        )
        FormulaPlan.new(
          formula:            formula_state.formula,
          path:               formula_state.path,
          subject:            subject,
          subject_kind:       suggestion.kind,
          generated_summary:  generated_summary,
          operations:         operations_for(formula_state),
        )
      end

      Plan.new(
        branch:         change_set.branch,
        base_ref:       change_set.base_ref,
        base_sha:       change_set.base_sha,
        head_sha:       change_set.head_sha,
        upstream_remote: change_set.upstream_remote,
        backup_branch:  backup_branch_name(change_set.branch),
        message_style:  resolved_style,
        formulas:       formula_plans,
      )
    end

    private

    def resolved_subject(formula_state:, suggestion:, single_formula_override:)
      return [@message, false] if single_formula_override

      if formula_state.existing_subject && @message.nil?
        return [formula_state.existing_subject, false]
      end

      [suggestion.subject, suggestion.generated_summary]
    end

    def operations_for(formula_state)
      operations = []
      operations << "split #{formula_state.split_commit_count} mixed commit(s)" if formula_state.split_commit_count.positive?
      operations << "squash #{formula_state.commits.length} commit(s) into 1" if formula_state.commits.length > 1
      if formula_state.dirty
        operations << if formula_state.commits.empty?
                        "create commit from working tree changes"
                      else
                        "amend with working tree changes"
                      end
      end
      operations << "create single commit" if operations.empty?
      operations
    end

    def print_preview(plan)
      @stdout.puts("Branch: #{plan.branch}")
      @stdout.puts("Base:   #{plan.base_ref} (#{plan.base_sha[0, 7]})")
      @stdout.puts("Style:  #{plan.message_style}")
      @stdout.puts("Mode:   #{@apply ? 'apply' : 'preview'}")
      @stdout.puts
      plan.formulas.each do |formula_plan|
        @stdout.puts("#{formula_plan.formula}")
        @stdout.puts("  path: #{formula_plan.path}")
        @stdout.puts("  plan: #{formula_plan.operations.join('; ')}")
        @stdout.puts("  commit: #{formula_plan.subject}#{formula_plan.generated_summary ? ' (generated fix summary)' : ''}")
      end
      @stdout.puts
      @stdout.puts("Push: #{@push ? "git push --force-with-lease #{plan.upstream_remote} #{plan.branch}" : 'disabled'}")
      @stdout.puts("PR:   #{@pr ? 'create/update through gh' : 'disabled'}")
      @stdout.puts("Backup branch: #{plan.backup_branch}") if @apply
      @stdout.puts
    end

    def apply_plan!(plan)
      repo.create_backup_branch(plan.backup_branch, plan.head_sha)
      repo.reset_to!(plan.base_sha)

      plan.formulas.each do |formula_plan|
        repo.add_path!(formula_plan.path)
        next unless repo.staged_changes_for?(formula_plan.path)

        repo.commit!(formula_plan.subject)
      end

      repo.push_force_with_lease!(plan.upstream_remote, plan.branch) if @push
    end

    def backup_branch_name(branch)
      timestamp = @time_source.call.strftime("%Y%m%d%H%M%S")
      "brew-dev-tools/#{branch}-backup-#{timestamp}"
    end

    def resolve_message_style
      return @message_style unless @message_style == :auto

      repo.homebrew_core? ? :homebrew : :conventional
    end
  end
end
