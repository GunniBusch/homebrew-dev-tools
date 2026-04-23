# Fish completion for brew-dev-tools external Homebrew commands.

function __fish_brew_dev_tools_using_command
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 2
    and test "$tokens[1]" = brew
    and test "$tokens[2]" = "$argv[1]"
end

function __fish_brew_dev_tools_formulae
    HOMEBREW_NO_AUTO_UPDATE=1 brew formulae 2>/dev/null
end

function __fish_brew_dev_tools_git_refs
    git for-each-ref --format="%(refname:short)" refs/heads refs/remotes 2>/dev/null
end

set -l __brew_dev_tools_bottle_tags all arm64_tahoe tahoe arm64_sequoia sequoia arm64_sonoma sonoma arm64_ventura ventura arm64_linux x86_64_linux

complete -c brew -n "__fish_brew_dev_tools_using_command prsync" -l apply -d "Rewrite the current branch from its merge-base"
complete -c brew -n "__fish_brew_dev_tools_using_command prsync" -l push -d "Push the rewritten branch with --force-with-lease"
complete -c brew -n "__fish_brew_dev_tools_using_command prsync" -l pr -d "Create or update the GitHub pull request after rewriting"
complete -c brew -n "__fish_brew_dev_tools_using_command prsync" -l ai -d "Force AI-assisted PR disclosure without detected wwdd AI context"
complete -c brew -n "__fish_brew_dev_tools_using_command prsync" -l message -r -d "Override the generated commit subject"
complete -c brew -n "__fish_brew_dev_tools_using_command prsync" -l style -r -a "auto homebrew conventional" -d "Commit/PR title style"
complete -c brew -n "__fish_brew_dev_tools_using_command prsync" -l base -r -a "(__fish_brew_dev_tools_git_refs)" -d "Override the base branch ref"
complete -c brew -n "__fish_brew_dev_tools_using_command prsync" -l help -d "Show help"
complete -c brew -n "__fish_brew_dev_tools_using_command prsync" -a "(__fish_brew_dev_tools_formulae)"

complete -c brew -n "__fish_brew_dev_tools_using_command wwdd" -l online -d "Pass --online through to brew audit"
complete -c brew -n "__fish_brew_dev_tools_using_command wwdd" -l install -d "Include brew install --build-from-source"
complete -c brew -n "__fish_brew_dev_tools_using_command wwdd" -l base -r -a "(__fish_brew_dev_tools_git_refs)" -d "Override the base branch ref"
complete -c brew -n "__fish_brew_dev_tools_using_command wwdd" -l help -d "Show help"
complete -c brew -n "__fish_brew_dev_tools_using_command wwdd" -a "(__fish_brew_dev_tools_formulae)"

complete -c brew -n "__fish_brew_dev_tools_using_command bottles" -l compare -d "Compare two formulae, or two tags for one formula"
complete -c brew -n "__fish_brew_dev_tools_using_command bottles" -l contents -d "Inspect the contents of a bottle archive"
complete -c brew -n "__fish_brew_dev_tools_using_command bottles" -l tag -r -a "$__brew_dev_tools_bottle_tags" -d "Bottle tag to inspect or compare"
complete -c brew -n "__fish_brew_dev_tools_using_command bottles" -l against-tag -r -a "$__brew_dev_tools_bottle_tags" -d "Second bottle tag for same-formula comparison"
complete -c brew -n "__fish_brew_dev_tools_using_command bottles" -l urls -d "Include full bottle URLs"
complete -c brew -n "__fish_brew_dev_tools_using_command bottles" -l help -d "Show help"
complete -c brew -n "__fish_brew_dev_tools_using_command bottles" -a "(__fish_brew_dev_tools_formulae)"
