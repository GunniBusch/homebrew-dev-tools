# frozen_string_literal: true

require_relative "test_helper"

class PrsyncIntegrationTest < BrewDevToolsTestCase
  def test_splits_mixed_commit_into_one_commit_per_formula
    with_tmpdir do |dir|
      init_repo(dir)
      remote = init_bare_remote(dir)
      attach_origin(dir, remote)
      commit_formula(dir, "foo", formula_content("foo", "1.0.0"), "foo 1.0.0 (new formula)")
      run_cmd(dir, "git", "push", "-u", "origin", "master")
      run_cmd(dir, "git", "checkout", "-b", "feature")

      File.write(dir/"Formula/foo.rb", formula_content("foo", "1.0.1"))
      File.write(dir/"Formula/bar.rb", formula_content("bar", "2.0.0"))
      run_cmd(dir, "git", "add", "--", "Formula/foo.rb", "Formula/bar.rb")
      run_cmd(dir, "git", "commit", "-m", "mixed commit")

      repo = BrewDevTools::GitRepo.new(path: dir, sign_commits: false)
      BrewDevTools::Prsync.new(
        repo: repo,
        stdout: StringIO.new,
        options: { apply: true, time_source: -> { Time.utc(2026, 4, 10, 10, 0, 0) } },
      ).run

      history = run_cmd(dir, "git", "log", "--format=%s", "origin/master..HEAD").lines.map(&:strip)
      assert_equal ["chore(foo): update to 1.0.1", "feat(bar): add new formula 2.0.0"], history.sort
    end
  end

  def test_squashes_multiple_commits_for_same_formula
    with_tmpdir do |dir|
      init_repo(dir)
      remote = init_bare_remote(dir)
      attach_origin(dir, remote)
      commit_formula(dir, "foo", formula_content("foo", "1.0.0"), "foo 1.0.0 (new formula)")
      run_cmd(dir, "git", "push", "-u", "origin", "master")
      run_cmd(dir, "git", "checkout", "-b", "feature")

      File.write(dir/"Formula/foo.rb", formula_content("foo", "1.0.1"))
      run_cmd(dir, "git", "add", "--", "Formula/foo.rb")
      run_cmd(dir, "git", "commit", "-m", "foo 1.0.1")
      File.write(dir/"Formula/foo.rb", formula_content("foo", "1.0.1", body: "depends_on \"bar\"\n"))
      run_cmd(dir, "git", "add", "--", "Formula/foo.rb")
      run_cmd(dir, "git", "commit", "-m", "foo: add dependency")

      repo = BrewDevTools::GitRepo.new(path: dir, sign_commits: false)
      BrewDevTools::Prsync.new(repo: repo, stdout: StringIO.new, options: { apply: true }).run

      history = run_cmd(dir, "git", "log", "--format=%s", "origin/master..HEAD").lines.map(&:strip)
      assert_equal ["foo 1.0.1"], history
    end
  end

  def test_reuses_existing_subject_when_amending_single_formula_commit
    with_tmpdir do |dir|
      init_repo(dir)
      remote = init_bare_remote(dir)
      attach_origin(dir, remote)
      commit_formula(dir, "foo", formula_content("foo", "1.0.0"), "foo 1.0.0 (new formula)")
      run_cmd(dir, "git", "push", "-u", "origin", "master")
      run_cmd(dir, "git", "checkout", "-b", "feature")

      File.write(dir/"Formula/foo.rb", formula_content("foo", "1.0.1"))
      run_cmd(dir, "git", "add", "--", "Formula/foo.rb")
      run_cmd(dir, "git", "commit", "-m", "foo 1.0.1")
      File.write(dir/"Formula/foo.rb", formula_content("foo", "1.0.1", body: "depends_on \"bar\"\n"))

      repo = BrewDevTools::GitRepo.new(path: dir, sign_commits: false)
      BrewDevTools::Prsync.new(repo: repo, stdout: StringIO.new, options: { apply: true }).run

      history = run_cmd(dir, "git", "log", "--format=%s", "origin/master..HEAD").lines.map(&:strip)
      assert_equal ["foo 1.0.1"], history
    end
  end

  def test_uses_force_with_lease_for_push
    with_tmpdir do |dir|
      init_repo(dir)
      remote = init_bare_remote(dir)
      attach_origin(dir, remote)
      commit_formula(dir, "foo", formula_content("foo", "1.0.0"), "foo 1.0.0 (new formula)")
      run_cmd(dir, "git", "push", "-u", "origin", "master")
      run_cmd(dir, "git", "checkout", "-b", "feature")
      run_cmd(dir, "git", "push", "-u", "origin", "feature")
      File.write(dir/"Formula/foo.rb", formula_content("foo", "1.0.1"))

      shell = Class.new(BrewDevTools::Shell) do
        attr_reader :commands

        def initialize
          super
          @commands = []
        end

        def run!(*command, **kwargs)
          @commands << command
          super
        end
      end.new

      repo = BrewDevTools::GitRepo.new(path: dir, shell: shell, sign_commits: false)
      BrewDevTools::Prsync.new(repo: repo, shell: shell, stdout: StringIO.new, options: { apply: true, push: true }).run

      assert shell.commands.any? { |cmd| cmd == ["git", "push", "--force-with-lease", "origin", "feature"] }
    end
  end

  def test_creates_or_updates_pr_through_gh
    with_tmpdir do |dir|
      init_repo(dir)
      remote = init_bare_remote(dir)
      attach_origin(dir, remote)
      commit_formula(dir, "foo", formula_content("foo", "1.0.0"), "foo 1.0.0 (new formula)")
      run_cmd(dir, "git", "push", "-u", "origin", "master")
      run_cmd(dir, "git", "checkout", "-b", "feature")
      run_cmd(dir, "git", "push", "-u", "origin", "feature")
      File.write(dir/"Formula/foo.rb", formula_content("foo", "1.0.1"))

      fake_bin = dir.parent/"#{dir.basename}-fake-bin"
      FileUtils.mkdir_p(fake_bin)
      log_file = dir/"gh.log"
      File.write(
        fake_bin/"gh",
        <<~SH,
          #!/bin/sh
          echo "$@" >> "#{log_file}"
          if [ "$1" = "auth" ]; then
            exit 0
          elif [ "$1" = "repo" ]; then
            echo master
          elif [ "$1" = "pr" ] && [ "$2" = "view" ]; then
            exit 1
          else
            exit 0
          fi
        SH
      )
      FileUtils.chmod("+x", fake_bin/"gh")

      shell = BrewDevTools::Shell.new(env: { "PATH" => "#{fake_bin}:#{ENV.fetch('PATH')}" })
      repo = BrewDevTools::GitRepo.new(path: dir, shell: shell, sign_commits: false)
      BrewDevTools::Prsync.new(
        repo: repo,
        shell: shell,
        stdout: StringIO.new,
        options: { apply: true, push: true, pr: true },
      ).run

      logged = File.read(log_file)
      assert_includes logged, "pr create"
      assert_includes logged, "--title chore(foo): update to 1.0.1"
    end
  end

  def test_uses_detected_wwdd_ai_context_without_ai_flag
    with_tmpdir do |dir|
      init_repo(dir)
      remote = init_bare_remote(dir)
      attach_origin(dir, remote)
      commit_formula(dir, "foo", formula_content("foo", "1.0.0"), "foo 1.0.0 (new formula)")
      run_cmd(dir, "git", "push", "-u", "origin", "master")
      run_cmd(dir, "git", "checkout", "-b", "feature")
      File.write(dir/"Formula/foo.rb", formula_content("foo", "1.0.1"))

      repo = BrewDevTools::GitRepo.new(path: dir, sign_commits: false)
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

      plan = BrewDevTools::Prsync.new(repo: repo, stdout: StringIO.new).build_plan(
        repo.inspect_change_set(formulas: [], base_ref: nil),
      )

      assert_equal true, plan.ai
    end
  end

  def test_rewrites_nested_formula_paths
    with_tmpdir do |dir|
      init_repo(dir)
      remote = init_bare_remote(dir)
      attach_origin(dir, remote)
      commit_formula(dir, "ripgrep", formula_content("ripgrep", "14.1.0"), "ripgrep 14.1.0 (new formula)", subdir: "r")
      run_cmd(dir, "git", "push", "-u", "origin", "master")
      run_cmd(dir, "git", "checkout", "-b", "feature")

      path = formula_file_path("ripgrep", subdir: "r")
      File.write(dir/path, formula_content("ripgrep", "14.1.1"))
      run_cmd(dir, "git", "add", "--", path)
      run_cmd(dir, "git", "commit", "-m", "ripgrep 14.1.1")

      repo = BrewDevTools::GitRepo.new(path: dir, sign_commits: false)
      BrewDevTools::Prsync.new(
        repo: repo,
        stdout: StringIO.new,
        options: { apply: true, formulas: ["ripgrep"] },
      ).run

      history = run_cmd(dir, "git", "log", "--format=%s", "origin/master..HEAD").lines.map(&:strip)
      assert_equal ["ripgrep 14.1.1"], history
    end
  end
end
