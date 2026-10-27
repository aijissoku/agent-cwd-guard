# agent-cwd-guard

English | [日本語](README.ja.md)

Stops **Claude Code** and **Codex CLI** from running on Windows when the working directory is a folder that web pages can write to without asking you.

## Why

A browser can put files in these places without any prompt:

| Location | What gets written |
|---|---|
| Downloads folder | The first download a site triggers is saved silently |
| `%LOCALAPPDATA%\Google\Chrome*` | Cookies, IndexedDB, caches, OPFS, ... |

If you start an AI coding agent in such a folder, any `CLAUDE.md`, `AGENTS.md` or `.claude/settings.json` sitting there (for example, from an extracted zip) is loaded as trusted project context. That opens the door to prompt injection and to project hooks running on your machine.

## How it works

Two layers:

1. **Machine-wide hooks (the main guard).** Registered in admin-only managed config, so neither user nor project settings can turn them off.
   - Claude Code: `C:\Program Files\ClaudeCode\managed-settings.json`
   - Codex CLI: `C:\ProgramData\OpenAI\Codex\requirements.toml`
   - `cwd_guard.py` runs on `SessionStart`, `UserPromptSubmit` and `PreToolUse`, and refuses when the working directory is one of the blocked folders.
2. **Launch-time check.** Wrappers for `claude` / `codex` in the PowerShell 7, Windows PowerShell 5.1 and Git Bash profiles refuse to start the CLI at all, before any project file is read.

The blocked folders are computed on every run, so the guard follows a relocated Downloads folder and per-profile Chrome download directories.

## Requirements

- Windows 10 / 11
- PowerShell 7 (`pwsh`) and administrator rights
- Python 3 (standard library only)
- Claude Code and/or Codex CLI with hook support (tested with Claude Code 2.1.300 and Codex CLI 0.162.1)

## How to use

### 1. Install

Pick one of the three ways below.

**A. One line** (any PowerShell window):

```powershell
irm https://raw.githubusercontent.com/aijissoku/agent-cwd-guard/main/get.ps1 | iex
```

It downloads the latest version to `%LOCALAPPDATA%\agent-cwd-guard` and runs `install.ps1` as administrator (you will see a UAC prompt). To pass options:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/aijissoku/agent-cwd-guard/main/get.ps1))) -NoProfiles
```

**B. Ask an AI agent** (Claude Code, Codex, ...). Start it in a normal folder, not in Downloads, and paste:

```text
Install agent-cwd-guard on this Windows machine: https://github.com/aijissoku/agent-cwd-guard
1. Read README.md, install.ps1 and cwd_guard.py first, and tell me in a few lines what will be changed on this PC.
2. Clone the repository into a normal folder (not Downloads), e.g. %USERPROFILE%\tools\agent-cwd-guard.
3. Check that PowerShell 7 (pwsh) and Python 3 are installed. If not, tell me what to install and stop.
4. install.ps1 needs administrator rights. If this session is not elevated, run:
   Start-Process pwsh -Verb RunAs -Wait -ArgumentList '-NoExit','-File','<clone path>\install.ps1'
   and wait for me to approve the UAC prompt.
5. Run test.ps1 -Live and report the result. If anything fails, show me the output; do not edit the managed config files by hand.
```

**C. Manually.** Open **PowerShell 7 as administrator** and run:

```powershell
git clone https://github.com/aijissoku/agent-cwd-guard.git
cd agent-cwd-guard
pwsh -File .\install.ps1
```

The installer:

- copies `cwd_guard.py` to `C:\ProgramData\AgentGuard`
- adds the hooks to the Claude Code and Codex managed config (existing settings are kept)
- makes those three folders writable by administrators and SYSTEM only
- adds the launch-time check to your PowerShell and Git Bash profiles

Running it again is safe; it produces the same result.

Options:

| Option | Effect |
|---|---|
| `-Python <path>` | Use a specific `python.exe` (auto-detected by default) |
| `-NoProfiles` | Do not touch shell profiles; install the managed hooks only |

### 2. Check that it works

Open a **new** terminal (profiles are read at startup), then:

```powershell
pwsh -File .\test.ps1        # path checks and hook responses
pwsh -File .\test.ps1 -Live  # also starts claude / codex in Downloads and confirms they are blocked
```

### 3. Everyday use

Use `claude` and `codex` as usual. In a blocked folder they refuse to start:

```
PS C:\Users\you\Downloads> claude
[AgentGuard] Claude CLI / Codex CLI cannot be used in this folder: C:\Users\you\Downloads
```

To work on something you downloaded, move or copy it to a normal project folder first, then start the agent there.

### 4. Change the blocked folders

Edit `forbidden()` in `cwd_guard.py`, then run `install.ps1` again. The message text is `MSG` in the same file.

### 5. Uninstall

```powershell
pwsh -File .\uninstall.ps1
```

Only what this tool added is removed; your other hooks and profile code stay as they are.

## Limitations

- It only looks at the **working directory**. An agent started elsewhere can still be asked to read files in Downloads. Treat it as one layer of defense, not a complete security boundary.
- If `requirements.toml` already contains a `[hooks]` section from another source, the installer leaves Codex alone and shows a warning; merge the hooks by hand in that case.
- The VS Code extensions and the Codex desktop app read the same managed config, but have not been tested.

## Files

| File | Purpose |
|---|---|
| `cwd_guard.py` | Path check and hook responses |
| `get.ps1` | One-line installer (download + elevated install) |
| `install.ps1` / `uninstall.ps1` | Install / uninstall |
| `common.ps1` | Shared paths and helpers |
| `profile-snippets/` | Wrappers inserted into shell profiles |
| `test.ps1` | Tests |

## License

[MIT](LICENSE)
