# frozen_string_literal: true

require_relative "test_helper"

class GitRepoTest < BrewDevToolsTestCase
  def test_detects_formula_paths_and_blocks_ambiguous_changes
    with_tmpdir do |dir|
      init_repo(dir)
      remote = init_bare_remote(dir)
      attach_origin(dir, remote)
      commit_formula(dir, "foo", formula_content("foo", "1.0.0"), "foo 1.0.0 (new formula)")
      run_cmd(dir, "git", "push", "-u", "origin", "master")
      run_cmd(dir, "git", "checkout", "-b", "feature")
      File.write(dir/"Formula/foo.rb", formula_content("foo", "1.0.1"))
      File.write(dir/"README.md", "noise")

      repo = BrewDevTools::GitRepo.new(path: dir)
      error = assert_raises(BrewDevTools::AmbiguousChangeError) { repo.inspect_change_set }
      assert_includes error.message, "README.md"
    end
  end

  def test_preview_plan_orders_formulas_from_history
    with_tmpdir do |dir|
      init_repo(dir)
      remote = init_bare_remote(dir)
      attach_origin(dir, remote)
      commit_formula(dir, "foo", formula_content("foo", "1.0.0"), "foo 1.0.0 (new formula)")
      run_cmd(dir, "git", "push", "-u", "origin", "master")
      run_cmd(dir, "git", "checkout", "-b", "feature")
      commit_formula(dir, "bar", formula_content("bar", "2.0.0"), "bar 2.0.0 (new formula)")
      File.write(dir/"Formula/foo.rb", formula_content("foo", "1.0.1"))
      run_cmd(dir, "git", "add", "--", "Formula/foo.rb")
      run_cmd(dir, "git", "commit", "-m", "foo 1.0.1")

      repo = BrewDevTools::GitRepo.new(path: dir)
      plan = BrewDevTools::Prsync.new(repo: repo, stdout: StringIO.new).run
      assert_equal %w[bar foo], plan.formulas.map(&:formula)
    end
  end

  def test_resolves_nested_formula_paths_for_explicit_formula_arguments
    with_tmpdir do |dir|
      init_repo(dir)
      remote = init_bare_remote(dir)
      attach_origin(dir, remote)
      commit_formula(dir, "ripgrep", formula_content("ripgrep", "14.1.0"), "ripgrep 14.1.0 (new formula)", subdir: "r")
      run_cmd(dir, "git", "push", "-u", "origin", "master")
      run_cmd(dir, "git", "checkout", "-b", "feature")
      path = formula_file_path("ripgrep", subdir: "r")
      File.write(dir/path, formula_content("ripgrep", "14.1.1"))

      repo = BrewDevTools::GitRepo.new(path: dir)
      change_set = repo.inspect_change_set(formulas: ["ripgrep"])

      assert_equal ["Formula/r/ripgrep.rb"], change_set.formula_states.map(&:path)
      assert_equal ["ripgrep"], change_set.formula_states.map(&:formula)
    end
  end

  def test_detects_head_owner_from_branch_remote
    with_tmpdir do |dir|
      init_repo(dir)
      remote = init_bare_remote(dir)
      attach_origin(dir, remote)
      run_cmd(dir, "git", "remote", "add", "gunnibusch", "git@github.com:GunniBusch/homebrew-core.git")
      commit_formula(dir, "foo", formula_content("foo", "1.0.0"), "foo 1.0.0 (new formula)")
      run_cmd(dir, "git", "checkout", "-b", "feature")
      run_cmd(dir, "git", "config", "branch.feature.remote", "gunnibusch")

      repo = BrewDevTools::GitRepo.new(path: dir)

      assert_equal "GunniBusch", repo.head_owner_for_branch("feature")
    end
  end
end
