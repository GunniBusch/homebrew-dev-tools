# frozen_string_literal: true

require_relative "test_helper"

class PRManagerTest < BrewDevToolsTestCase
  class FakeRepo
    attr_reader :path

    def initialize(path:, head_owner: nil, homebrew_core: false, pull_request_template: nil)
      @path = path
      @head_owner = head_owner
      @homebrew_core = homebrew_core
      @pull_request_template = pull_request_template
    end

    def homebrew_core?
      @homebrew_core
    end

    def default_branch_name
      "main"
    end

    def git_dir
      File.join(path, ".git")
    end

    def head_owner_for_branch(_branch)
      @head_owner
    end

    def pull_request_template
      @pull_request_template
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
        ai: false,
        closes: [],
        fixes: [],
        references: [],
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
      repo = FakeRepo.new(path: dir.to_s, head_owner: "gunnibusch")
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
        ai: false,
        closes: [],
        fixes: [],
        references: [],
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

      view = shell.commands.find { |command| command[0, 3] == ["gh", "pr", "view"] }
      assert_includes view, "gunnibusch:feature"
      edit = shell.commands.find { |command| command[0, 3] == ["gh", "pr", "edit"] }
      refute_nil edit
      assert_includes edit, "42"
      refute shell.commands.any? { |command| command[0, 3] == ["gh", "pr", "create"] }
    end
  end

  def test_creates_new_pr_when_branch_has_no_open_pr
    with_tmpdir do |dir|
      repo = FakeRepo.new(path: dir.to_s, head_owner: "gunnibusch")
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
        ai: false,
        closes: [],
        fixes: [],
        references: [],
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

      view = shell.commands.find { |command| command[0, 3] == ["gh", "pr", "view"] }
      assert_includes view, "gunnibusch:feature"
      create = shell.commands.find { |command| command[0, 3] == ["gh", "pr", "create"] }
      refute_nil create
      assert_includes create, "--head"
      assert_includes create, "gunnibusch:feature"
    end
  end

  def test_marks_homebrew_core_ai_checkbox_when_opted_in
    with_tmpdir do |dir|
      repo = FakeRepo.new(
        path: dir.to_s,
        homebrew_core: true,
        pull_request_template: <<~TEMPLATE,
          -----
          - [ ] Have you ensured that your commits follow the [commit style guide](https://docs.brew.sh/Formula-Cookbook#commit)?
          - [ ] Is your test running fine `brew test <formula>`?
          -----
          - [ ] AI was used to generate or assist with generating this PR. *Please specify below how you used AI to help you, and what steps you have taken to manually verify the changes*.
          -----
        TEMPLATE
      )
      shell = CaptureShell.new
      manager = BrewDevTools::PRManager.new(repo: repo, shell: shell, stdout: StringIO.new)
      BrewDevTools::ValidationStore.save(
        repo: repo,
        report: {
          "formulas" => [
            {
              "formula" => "foo",
              "steps" => [
                { "name" => "test", "success" => true },
              ],
            },
          ],
          "ai" => {
            "detected" => true,
            "tool" => "Codex",
            "source" => "env",
            "detail" => "Detected via CODEX_SHELL.",
          },
        },
      )
      plan = BrewDevTools::Prsync::Plan.new(
        branch: "feature",
        base_ref: "origin/main",
        base_sha: "abc123",
        head_sha: "def456",
        upstream_remote: "origin",
        backup_branch: "backup/feature",
        message_style: :homebrew,
        ai: true,
        closes: [],
        fixes: [],
        references: [],
        formulas: [
          BrewDevTools::Prsync::FormulaPlan.new(
            formula: "foo",
            path: "Formula/foo.rb",
            subject: "foo 1.2.3",
            subject_kind: :version_bump,
            generated_summary: false,
            operations: ["create single commit"],
          ),
        ],
      )

      manager.sync_pr!(plan)

      create = shell.commands.find { |command| command[0, 3] == ["gh", "pr", "create"] }
      body = create[create.index("--body") + 1]
      assert_includes body, "- [x] AI was used to generate or assist with generating this PR."
      assert_includes body, "AI/LLM usage: Codex."
      assert_includes body, "I manually reviewed the generated changes"
    end
  end

  def test_appends_reference_footer_lines_to_pr_body
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
        ai: false,
        closes: ["123", "owner/repo#45"],
        fixes: ["#88"],
        references: ["https://github.com/Homebrew/homebrew-core/pull/123456"],
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
      body = create[create.index("--body") + 1]
      assert_includes body, "Closes #123"
      assert_includes body, "Closes owner/repo#45"
      assert_includes body, "Fixes #88"
      assert_includes body, "References https://github.com/Homebrew/homebrew-core/pull/123456"
    end
  end

  def test_does_not_mark_homebrew_core_ai_checkbox_without_ai_plan
    with_tmpdir do |dir|
      repo = FakeRepo.new(
        path: dir.to_s,
        homebrew_core: true,
        pull_request_template: <<~TEMPLATE,
          -----
          - [ ] Have you ensured that your commits follow the [commit style guide](https://docs.brew.sh/Formula-Cookbook#commit)?
          - [ ] Is your test running fine `brew test <formula>`?
          -----
          - [ ] AI was used to generate or assist with generating this PR. *Please specify below how you used AI to help you, and what steps you have taken to manually verify the changes*.
          -----
        TEMPLATE
      )
      shell = CaptureShell.new
      manager = BrewDevTools::PRManager.new(repo: repo, shell: shell, stdout: StringIO.new)
      BrewDevTools::ValidationStore.save(
        repo: repo,
        report: {
          "formulas" => [
            {
              "formula" => "foo",
              "steps" => [
                { "name" => "test", "success" => true },
              ],
            },
          ],
          "ai" => {
            "detected" => true,
            "tool" => "Codex",
            "source" => "env",
            "detail" => "Detected via CODEX_SHELL.",
          },
        },
      )
      plan = BrewDevTools::Prsync::Plan.new(
        branch: "feature",
        base_ref: "origin/main",
        base_sha: "abc123",
        head_sha: "def456",
        upstream_remote: "origin",
        backup_branch: "backup/feature",
        message_style: :homebrew,
        ai: false,
        closes: [],
        fixes: [],
        references: [],
        formulas: [
          BrewDevTools::Prsync::FormulaPlan.new(
            formula: "foo",
            path: "Formula/foo.rb",
            subject: "foo 1.2.3",
            subject_kind: :version_bump,
            generated_summary: false,
            operations: ["create single commit"],
          ),
        ],
      )

      manager.sync_pr!(plan)

      create = shell.commands.find { |command| command[0, 3] == ["gh", "pr", "create"] }
      body = create[create.index("--body") + 1]
      refute_includes body, "- [x] AI was used to generate or assist with generating this PR."
      refute_includes body, "AI/LLM usage: Codex."
    end
  end
end
