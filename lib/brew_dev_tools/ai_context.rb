# frozen_string_literal: true

module BrewDevTools
  class AIContext
    SIGNALS = [
      { env: "CODEX_SHELL", tool: "Codex", detail: "Detected via CODEX_SHELL." },
      { env: "CODEX_CI", tool: "Codex", detail: "Detected via CODEX_CI." },
      { env: "CLAUDECODE", tool: "Claude Code", detail: "Detected via CLAUDECODE." },
      { env: "AIDER_MODEL", tool: "Aider", detail: "Detected via AIDER_MODEL." },
      { env: "CURSOR_TRACE_ID", tool: "Cursor", detail: "Detected via CURSOR_TRACE_ID." },
      { env: "AMP_CODEX", tool: "Amp", detail: "Detected via AMP_CODEX." },
      { env: "GEMINI_CLI", tool: "Gemini CLI", detail: "Detected via GEMINI_CLI." },
    ].freeze

    PROCESS_SIGNALS = [
      { pattern: %r{(?:^|/)(?:Codex|codex)(?:\.app)?(?:$|/)}i, tool: "Codex" },
      { pattern: /Claude(?:\.app)?|claude/i, tool: "Claude Code" },
      { pattern: /cursor/i, tool: "Cursor" },
      { pattern: /aider/i, tool: "Aider" },
      { pattern: /gemini/i, tool: "Gemini CLI" },
      { pattern: /amp/i, tool: "Amp" },
    ].freeze

    def initialize(env: ENV, pid: Process.pid, process_ancestry_loader: nil)
      @env = env
      @pid = pid
      @process_ancestry_loader = process_ancestry_loader || method(:default_process_ancestry)
    end

    def detect
      signal = SIGNALS.find { |entry| truthy_env?(entry.fetch(:env)) }
      return detected(tool: signal.fetch(:tool), source: "env", detail: signal.fetch(:detail)) if signal

      ancestry_signal = detected_from_process_ancestry
      return ancestry_signal if ancestry_signal

      undetected
    end

    private

    def detected_from_process_ancestry
      commands = @process_ancestry_loader.call(@pid)
      signal = PROCESS_SIGNALS.find do |entry|
        commands.any? { |command| command.match?(entry.fetch(:pattern)) }
      end
      return nil unless signal

      detected(
        tool: signal.fetch(:tool),
        source: "process",
        detail: "Detected via process ancestry.",
      )
    end

    def detected(tool:, source:, detail:)
      {
        "detected" => true,
        "tool" => tool,
        "source" => source,
        "detail" => detail,
      }
    end

    def undetected
      {
        "detected" => false,
        "tool" => nil,
        "source" => nil,
        "detail" => nil,
      }
    end

    def truthy_env?(key)
      value = @env[key]
      value && !value.empty? && value != "0" && value.casecmp("false") != 0
    end

    def default_process_ancestry(pid)
      commands = []
      current_pid = pid
      visited = {}

      while current_pid && current_pid.positive? && !visited[current_pid]
        visited[current_pid] = true
        parent_pid, command = process_info(current_pid)
        break unless parent_pid

        commands << command if command && !command.empty?
        current_pid = parent_pid
      end

      commands
    end

    def process_info(pid)
      stdout, _stderr, status = Open3.capture3("ps", "-o", "ppid=,comm=", "-p", pid.to_s)
      return [nil, nil] unless status.success?

      line = stdout.lines.first&.strip
      return [nil, nil] if line.nil? || line.empty?

      parts = line.split(/\s+/, 2)
      parent_pid = parts.first.to_i
      command = parts[1]
      [parent_pid, command]
    rescue StandardError
      [nil, nil]
    end
  end
end
