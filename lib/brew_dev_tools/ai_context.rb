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

    def initialize(env: ENV)
      @env = env
    end

    def detect
      signal = SIGNALS.find { |entry| truthy_env?(entry.fetch(:env)) }
      return undetected unless signal

      {
        "detected" => true,
        "tool" => signal.fetch(:tool),
        "source" => "env",
        "detail" => signal.fetch(:detail),
      }
    end

    private

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
  end
end
