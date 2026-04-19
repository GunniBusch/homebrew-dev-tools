# frozen_string_literal: true

module BrewDevTools
  class GitRepo
    FormulaState = Struct.new(
      :formula,
      :path,
      :new_formula,
      :commits,
      :existing_subject,
      :split_commit_count,
      :dirty,
      :base_content,
      :final_content,
      keyword_init: true,
    )

    ChangeSet = Struct.new(
      :branch,
      :head_sha,
      :base_ref,
      :base_sha,
      :upstream_remote,
      :formula_states,
      :ambiguous_paths,
      keyword_init: true,
    )

    attr_reader :path

    def initialize(path:, shell: Shell.new, sign_commits: true)
      @path = File.expand_path(path)
      @shell = shell
      @sign_commits = sign_commits
    end

    def ensure_git_repo!
      run_git!("rev-parse", "--show-toplevel")
    rescue CommandError => e
      raise GitError, "Not a git repository: #{path} (#{e.message})"
    end

    def git_dir
      @git_dir ||= run_git!("rev-parse", "--git-dir").stdout.strip.then do |dir|
        File.expand_path(dir, path)
      end
    end

    def current_branch
      run_git!("branch", "--show-current").stdout.strip
    end

    def head_sha
      run_git!("rev-parse", "HEAD").stdout.strip
    end

    def upstream_remote
      branch_remote(current_branch)
    end

    def branch_remote(branch)
      result = run_git!("config", "--get", "branch.#{branch}.remote", allow_failure: true)
      remote = result.stdout.strip
      remote.empty? ? "origin" : remote
    end

    def default_base_remote
      branch_remote = upstream_remote
      remotes = git_remotes
      parent_remote = github_parent_remote_for(branch_remote, remotes)
      return parent_remote if parent_remote
      return "upstream" if remotes.include?("upstream") && branch_remote != "upstream"
      return "origin" if remotes.include?("origin") && branch_remote != "origin"

      branch_remote
    end

    def remote_url(remote)
      run_git!("remote", "get-url", remote).stdout.strip
    rescue CommandError
      nil
    end

    def head_owner_for_branch(branch)
      remote = branch_remote(branch)
      github_owner_from_remote_url(remote_url(remote))
    end

    def default_base_ref
      symbolic = run_git!("symbolic-ref", "refs/remotes/#{default_base_remote}/HEAD", allow_failure: true).stdout.strip
      return symbolic.sub(%r{\Arefs/remotes/}, "") unless symbolic.empty?

      %W[#{default_base_remote}/master #{default_base_remote}/main master main].find do |candidate|
        run_git!("rev-parse", "--verify", candidate, allow_failure: true).success?
      end || raise(GitError, "Could not determine a base branch for #{current_branch}")
    end

    def merge_base(base_ref = default_base_ref)
      run_git!("merge-base", base_ref, "HEAD").stdout.strip
    end

    def homebrew_core?
      root = File.basename(path)
      root == "homebrew-core" || path.end_with?("/homebrew/homebrew-core")
    end

    def pull_request_template
      template = File.join(path, ".github", "PULL_REQUEST_TEMPLATE.md")
      return nil unless File.exist?(template)

      File.read(template)
    end

    def inspect_change_set(formulas: [], base_ref: nil)
      ensure_git_repo!
      base_ref ||= default_base_ref
      base_sha = merge_base(base_ref)

      committed_entries = diff_name_status("#{base_sha}..HEAD")
      dirty_entries = diff_name_status("HEAD")
      untracked_entries = untracked_name_status

      committed_formula_paths, committed_ambiguous = classify_entries(committed_entries)
      dirty_formula_paths, dirty_ambiguous = classify_entries(dirty_entries + untracked_entries)
      ambiguous_paths = (committed_ambiguous + dirty_ambiguous).uniq.sort
      unless ambiguous_paths.empty?
        raise AmbiguousChangeError,
              "Changed files outside Formula/**/*.rb are not supported: #{ambiguous_paths.join(', ')}"
      end

      all_formula_paths = (committed_formula_paths + dirty_formula_paths).uniq.sort
      requested_paths = resolve_requested_paths(all_formula_paths, formulas)
      raise ValidationError, "No changed formula files found on this branch." if requested_paths.empty?

      commit_ids = branch_commits_since(base_sha)
      commit_formula_map = {}
      commit_ids.each do |commit|
        entries = diff_tree_name_status(commit)
        formula_paths, extra_paths = classify_entries(entries)
        unless extra_paths.empty?
          raise AmbiguousChangeError,
                "Commit #{commit[0, 7]} touches unsupported files: #{extra_paths.join(', ')}"
        end
        commit_formula_map[commit] = formula_paths
      end

      ordered_paths = if formulas.empty?
        order_from_history(commit_ids, commit_formula_map, requested_paths)
      else
        requested_paths
      end

      formula_states = ordered_paths.map do |formula_path|
        commit_list = commit_ids.select { |commit| commit_formula_map.fetch(commit).include?(formula_path) }
        FormulaState.new(
          formula:            FormulaInspector.formula_name_from_path(formula_path),
          path:               formula_path,
          new_formula:        !path_exists_at?(base_sha, formula_path),
          commits:            commit_list,
          existing_subject:   reusable_commit_subject(commit_list, commit_formula_map),
          split_commit_count: commit_list.count { |commit| commit_formula_map.fetch(commit).size > 1 },
          dirty:              dirty_formula_paths.include?(formula_path),
          base_content:       file_content_at(base_sha, formula_path),
          final_content:      working_tree_content(formula_path) || file_content_at("HEAD", formula_path),
        )
      end

      ChangeSet.new(
        branch:          current_branch,
        head_sha:        head_sha,
        base_ref:        base_ref,
        base_sha:        base_sha,
        upstream_remote: upstream_remote,
        formula_states:  formula_states,
        ambiguous_paths: ambiguous_paths,
      )
    end

    def default_branch_name
      result = @shell.run!(
        "gh", "repo", "view", "--json", "defaultBranchRef", "--jq", ".defaultBranchRef.name",
        chdir: path,
      )
      result.stdout.strip
    rescue CommandError
      default_base_ref.split("/").last
    end

    def branch_commits_since(base_sha)
      output = run_git!("rev-list", "--reverse", "#{base_sha}..HEAD").stdout.strip
      output.empty? ? [] : output.lines.map(&:strip)
    end

    def create_backup_branch(name, sha)
      run_git!("branch", name, sha)
    end

    def reset_to!(ref)
      run_git!("reset", "--mixed", ref)
    end

    def add_path!(pathspec)
      run_git!("add", "--", pathspec)
    end

    def staged_changes_for?(pathspec)
      !run_git!("diff", "--cached", "--quiet", "--", pathspec, allow_failure: true).success?
    end

    def commit!(message)
      args = ["commit"]
      args << "-S" if @sign_commits
      args += ["-m", message]
      run_git!(*args)
    end

    def push_force_with_lease!(remote, branch)
      run_git!("push", "--force-with-lease", remote, branch)
    end

    def relative_path(pathspec)
      File.join(path, pathspec)
    end

    def path_exists_at?(ref, pathspec)
      run_git!("cat-file", "-e", "#{ref}:#{pathspec}", allow_failure: true).success?
    end

    def file_content_at(ref, pathspec)
      return nil unless path_exists_at?(ref, pathspec)

      run_git!("show", "#{ref}:#{pathspec}").stdout
    end

    private

    def github_owner_from_remote_url(url)
      return nil if url.nil? || url.empty?

      patterns = [
        %r{\Ahttps?://github\.com/([^/]+)/[^/]+(?:\.git)?\z}i,
        %r{\Agit@github\.com:([^/]+)/[^/]+(?:\.git)?\z}i,
        %r{\Assh://git@github\.com/([^/]+)/[^/]+(?:\.git)?\z}i,
      ]
      match = patterns.lazy.map { |pattern| url.match(pattern) }.find(&:itself)
      match && match[1]
    end

    def git_remotes
      run_git!("remote").stdout.lines.map(&:strip)
    end

    def github_parent_remote_for(remote_name, remotes = git_remotes)
      remote_repo = github_repo_name_for_remote(remote_name)
      return nil if remote_repo.nil?

      result = @shell.run!(
        "gh", "repo", "view", remote_repo, "--json", "parent", "--jq", ".parent.nameWithOwner // \"\"",
        chdir: path,
        allow_failure: true,
      )
      parent_repo = result.stdout.strip
      return nil if parent_repo.empty?

      remotes.find { |candidate| github_repo_name_for_remote(candidate) == parent_repo }
    rescue CommandError
      nil
    end

    def github_repo_name_for_remote(remote_name)
      url = run_git!("remote", "get-url", remote_name, allow_failure: true).stdout.strip
      return nil if url.empty?

      github_repo_name_from_url(url)
    end

    def github_repo_name_from_url(url)
      match = url.match(%r{\A(?:https://github\.com/|git@github\.com:)([^/]+/[^/.]+)(?:\.git)?\z})
      match&.captures&.first
    end

    def resolve_requested_paths(all_formula_paths, formulas)
      return all_formula_paths if formulas.empty?

      requested_paths = formulas.map do |formula|
        matches = FormulaInspector.matching_formula_paths(formula, all_formula_paths)
        if matches.empty?
          raise ValidationError, "Requested formula `#{formula}` is not changed on this branch."
        end

        if matches.length > 1
          raise ValidationError,
                "Requested formula `#{formula}` matches multiple changed paths: #{matches.join(', ')}"
        end

        matches.first
      end

      extra = all_formula_paths - requested_paths
      unless extra.empty?
        raise ValidationError,
              "Formula arguments must cover every changed formula on the branch: #{extra.map { |path| FormulaInspector.formula_name_from_path(path) }.join(', ')}"
      end

      requested_paths
    end

    def reusable_commit_subject(commit_list, commit_formula_map)
      reusable_commit = commit_list.find { |commit| commit_formula_map.fetch(commit).length == 1 }
      return nil unless reusable_commit

      run_git!("show", "-s", "--format=%s", reusable_commit).stdout.strip
    end

    def order_from_history(commit_ids, commit_formula_map, requested_paths)
      seen = []
      commit_ids.each do |commit|
        commit_formula_map.fetch(commit).each do |formula_path|
          next unless requested_paths.include?(formula_path)
          next if seen.include?(formula_path)

          seen << formula_path
        end
      end

      (seen + (requested_paths - seen).sort).uniq
    end

    def working_tree_content(pathspec)
      file = relative_path(pathspec)
      return nil unless File.exist?(file)

      File.read(file)
    end

    def diff_name_status(range)
      output = run_git!("diff", "--name-status", range, allow_failure: true).stdout
      parse_name_status(output)
    end

    def diff_tree_name_status(commit)
      output = run_git!("diff-tree", "--no-commit-id", "--name-status", "-r", commit).stdout
      parse_name_status(output)
    end

    def untracked_name_status
      output = run_git!("ls-files", "--others", "--exclude-standard").stdout
      output.lines.map { |line| ["??", line.strip] }
    end

    def classify_entries(entries)
      formula_paths = []
      ambiguous_paths = []

      entries.each do |_status, pathspec|
        next if pathspec.nil? || pathspec.empty?

        if FormulaInspector.formula_path?(pathspec)
          formula_paths << pathspec
        else
          ambiguous_paths << pathspec
        end
      end

      [formula_paths.uniq.sort, ambiguous_paths.uniq.sort]
    end

    def parse_name_status(output)
      output.lines.filter_map do |line|
        parts = line.strip.split("\t")
        next if parts.empty?

        status = parts.first
        pathspec = if status.start_with?("R", "C")
          parts.last
        else
          parts[1]
        end

        [status, pathspec]
      end
    end

    def run_git!(*args, allow_failure: false)
      @shell.run!("git", *args, chdir: path, allow_failure: allow_failure)
    end
  end
end
