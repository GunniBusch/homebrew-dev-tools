# frozen_string_literal: true

require_relative "test_helper"

class PRManagerTest < BrewDevToolsTestCase
  class FakeRepo
    attr_reader :path

    def initialize(path:)
      @path = path
    end

    def homebrew_core?
      false
    end

    def default_branch_name
      "main"
    end

    def git_dir
      File.join(path, ".git")
    end
  end

  class CaptureShell < BrewDevTools::Shell
    attr_reader :commands

    def initialize(pr_view_result: nil, **kwargs)
      super(**kwargs)
      @commands = []
      @pr_view_result = pr_view_result
    end

    def run!(*command, **kwargs)
      @commands << command
      if command[0, 3] == ["gh", "pr", "view"]
        if @pr_view_result
          BrewDevTools::Shell::Result.new(
            command: command,
            status: 0,
            stdout: JSON.dump(@pr_view_result),
            stderr: "",
          )
        else
          BrewDevTools::Shell::Result.new(command: command, status: 1, stdout: "", stderr: "no pull requests found")
        end
      elsif command[0, 3] == ["gh", "auth", "status"]
        BrewDevTools::Shell::Result.new(command: command, status: 0, stdout: "", stderr: "")
      elsif command[0, 3] == ["gh", "pr", "create"]
        BrewDevTools::Shell::Result.new(command: command, status: 0, stdout: "https://example.test/pr/1\n", stderr: "")
      elsif command[0, 3] == ["gh", "pr", "edit"]
        BrewDevTools::Shell::Result.new(command: command, status: 0, stdout: "", stderr: "")
      else
        super
      end
    end
  end

  def test_conventional_pr_title_for_multiple_formulae
    with_tmpdir do |dir|
      repo = FakeRepo.new(path: dir.to_s)
      shell = CaptureShell.new
      manager = BrewDevTools::PRManager.new(repo: repo, shell: shell, stdout: StringIO.new)
      plan = BrewDevTools::Prsync::Plan.new(
        branch: "feature",
        base_ref: "origin/main",
        base_sha: "abc123",
        head_sha: "def456",
        upstream_remote: "origin",
        backup_branch: "backup/feature",
        message_style: :conventional,
        formulas: [
          BrewDevTools::Prsync::FormulaPlan.new(
            formula: "foo",
            path: "Formula/foo.rb",
            subject: "chore(foo): update to 1.2.3",
            subject_kind: :version_bump,
            generated_summary: false,
            operations: ["create single commit"],
          ),
          BrewDevTools::Prsync::FormulaPlan.new(
            formula: "bar",
            path: "Formula/bar.rb",
            subject: "chore(bar): update to 2.0.0",
            subject_kind: :version_bump,
            generated_summary: false,
            operations: ["create single commit"],
          ),
        ],
      )

      manager.sync_pr!(plan)

      create = shell.commands.find { |command| command[0, 3] == ["gh", "pr", "create"] }
      assert_includes create, "chore: update 2 formulae"
    end
  end

  def test_updates_existing_open_pr_for_current_branch
    with_tmpdir do |dir|
      repo = FakeRepo.new(path: dir.to_s)
      shell = CaptureShell.new(pr_view_result: { "number" => 42, "title" => "old", "url" => "https://example.test/pr/42", "state" => "OPEN" })
      manager = BrewDevTools::PRManager.new(repo: repo, shell: shell, stdout: StringIO.new)
      plan = BrewDevTools::Prsync::Plan.new(
        branch: "feature",
        base_ref: "origin/main",
        base_sha: "abc123",
        head_sha: "def456",
        upstream_remote: "origin",
        backup_branch: "backup/feature",
        message_style: :conventional,
        formulas: [
          BrewDevTools::Prsync::FormulaPlan.new(
            formula: "foo",
            path: "Formula/foo.rb",
            subject: "chore(foo): update to 1.2.3",
            subject_kind: :version_bump,
            generated_summary: false,
            operations: ["create single commit"],
          ),
        ],
      )

      manager.sync_pr!(plan)

      edit = shell.commands.find { |command| command[0, 3] == ["gh", "pr", "edit"] }
      refute_nil edit
      assert_includes edit, "42"
      refute shell.commands.any? { |command| command[0, 3] == ["gh", "pr", "create"] }
    end
  end

  def test_creates_new_pr_when_branch_has_no_open_pr
    with_tmpdir do |dir|
      repo = FakeRepo.new(path: dir.to_s)
      shell = CaptureShell.new
      manager = BrewDevTools::PRManager.new(repo: repo, shell: shell, stdout: StringIO.new)
      plan = BrewDevTools::Prsync::Plan.new(
        branch: "feature",
        base_ref: "origin/main",
        base_sha: "abc123",
        head_sha: "def456",
        upstream_remote: "origin",
        backup_branch: "backup/feature",
        message_style: :conventional,
        formulas: [
          BrewDevTools::Prsync::FormulaPlan.new(
            formula: "foo",
            path: "Formula/foo.rb",
            subject: "chore(foo): update to 1.2.3",
            subject_kind: :version_bump,
            generated_summary: false,
            operations: ["create single commit"],
          ),
        ],
      )

      manager.sync_pr!(plan)

      create = shell.commands.find { |command| command[0, 3] == ["gh", "pr", "create"] }
      refute_nil create
      assert_includes create, "--head"
      assert_includes create, "feature"
    end
  end
end
