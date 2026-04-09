# frozen_string_literal: true

module BrewDevTools
  class Shell
    Result = Struct.new(:command, :status, :stdout, :stderr, keyword_init: true) do
      def success?
        status.zero?
      end
    end

    def initialize(env: {})
      @env = env
    end

    def run!(*command, chdir: nil, env: {}, allow_failure: false)
      stdout, stderr, status = Open3.capture3(@env.merge(env), *command, chdir: chdir)
      result = Result.new(
        command: command,
        status: status.exitstatus,
        stdout: stdout,
        stderr: stderr,
      )
      return result if allow_failure || result.success?

      raise CommandError,
            "Command failed (#{command.join(' ')}): #{stderr.strip.empty? ? stdout.strip : stderr.strip}"
    end
  end
end
