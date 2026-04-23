# frozen_string_literal: true

module BrewDevTools
  class Wwdd
    def initialize(repo:, shell: Shell.new, stdout: $stdout, options: {})
      @repo = repo
      @shell = shell
      @stdout = stdout
      @formulas = options.fetch(:formulas, [])
      @online = options.fetch(:online, false)
      @install = options.fetch(:install, false)
      @brew_executable = options.fetch(:brew_executable, ENV.fetch("HOMEBREW_BREW_FILE", "brew"))
      @base_ref = options[:base_ref]
      @time_source = options[:time_source] || -> { Time.now.utc }
      @ai_context = options[:ai_context] || AIContext.new
    end

    def run
      change_set = @repo.inspect_change_set(formulas: @formulas, base_ref: @base_ref)
      report = {
        "generated_at" => @time_source.call.iso8601,
        "branch" => change_set.branch,
        "head_sha" => change_set.head_sha,
        "ai" => @ai_context.detect,
        "formulas" => [],
      }

      change_set.formula_states.each do |formula_state|
        @stdout.puts("==> #{formula_state.formula}")
        formula_report = {
          "formula" => formula_state.formula,
          "new_formula" => formula_state.new_formula,
          "steps" => [],
        }
        steps_for(formula_state).each do |step|
          formula_report["steps"] << run_step(step)
        end
        report["formulas"] << formula_report
        @stdout.puts
      end

      ValidationStore.save(repo: @repo, report: report)
      print_summary(report)
      report
    end

    private

    def steps_for(formula_state)
      audit_mode = formula_state.new_formula ? "--new" : "--strict"

      [
        { name: "style", command: [@brew_executable, "style", "--fix", "--formula", formula_state.formula], env: {} },
        (@install ? { name: "install", command: [@brew_executable, "install", "--build-from-source", formula_state.formula], env: { "HOMEBREW_NO_INSTALL_FROM_API" => "1" } } : nil),
        { name: "test", command: [@brew_executable, "test", formula_state.formula], env: {} },
        { name: "audit", command: [@brew_executable, "audit", audit_mode, *(@online ? ["--online"] : []), formula_state.formula], env: {} },
      ].compact
    end

    def run_step(step)
      command = Array(step.fetch(:command))
      @stdout.puts("  $ #{format_command(command, step.fetch(:env))}")
      result = @shell.run!(*command, chdir: @repo.path, env: step.fetch(:env), allow_failure: true)
      output = [result.stdout, result.stderr].reject(&:empty?).join
      @stdout.print(indent_output(output)) unless output.empty?
      success = result.success?
      @stdout.puts("  -> #{success ? 'pass' : 'fail'}")
      {
        "name" => step.fetch(:name),
        "command" => command.join(" "),
        "success" => success,
      }
    end

    def print_summary(report)
      all_success = report.fetch("formulas").all? do |formula_report|
        formula_report.fetch("steps").all? { |step| step.fetch("success") }
      end
      ai = report.fetch("ai")

      @stdout.puts("Summary:")
      report.fetch("formulas").each do |formula_report|
        statuses = formula_report.fetch("steps").map do |step|
          "#{step.fetch('name')}: #{step.fetch('success') ? 'pass' : 'fail'}"
        end
        @stdout.puts("  #{formula_report.fetch('formula')}: #{statuses.join(', ')}")
      end
      if ai.fetch("detected")
        @stdout.puts("  AI context: #{ai.fetch('tool')} (#{ai.fetch('source')})")
      else
        @stdout.puts("  AI context: not detected")
      end
      @stdout.puts(all_success ? "WWDD: ready" : "WWDD: failed")
    end

    def format_command(command, env)
      env_prefix = env.map { |key, value| "#{key}=#{value}" }.join(" ")
      [env_prefix, *command].reject(&:empty?).join(" ")
    end

    def indent_output(output)
      output.lines.map { |line| "    #{line}" }.join
    end
  end
end
