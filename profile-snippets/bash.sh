# agent-cwd-guard: do not start claude / codex in Downloads or Chrome's data folders (Git Bash).
# install.ps1 fills in the paths and inserts this block at the top of ~/.bashrc.
_agentguard_ok() { "__PYTHON__" -I "__GUARD__" --check "$(pwd -W 2>/dev/null || pwd)"; [ $? -ne 2 ]; }
claude() { _agentguard_ok || return 2; command claude "$@"; }
codex() { _agentguard_ok || return 2; command codex "$@"; }
