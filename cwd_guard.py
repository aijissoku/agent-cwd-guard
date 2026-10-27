"""agent-cwd-guard: block Claude Code / Codex CLI in folders web pages can write to.

Blocked folders = places a browser can write files to without asking:
  - the Downloads folder (Windows known folder + each Chrome profile's download directory)
  - Chrome's user data (%LOCALAPPDATA%\\Google\\Chrome*)
This keeps a planted CLAUDE.md / AGENTS.md / .claude/ from being loaded as project context.

Two modes:
  1. Hook: reads the hook JSON on stdin and, if the working directory is blocked, prints a
     JSON refusal (SessionStart / UserPromptSubmit / PreToolUse; same for Claude Code and Codex).
  2. Launch check: `python cwd_guard.py --check <dir>` exits with code 2 if <dir> is blocked.
"""
import glob
import json
import os
import sys
import winreg

# Known folder GUID of the Downloads folder
DOWNLOADS_GUID = '{374DE290-123F-4565-9164-39C4925E467B}'

MSG = ('[AgentGuard] Claude CLI / Codex CLI cannot be used in this folder: {cwd}\n'
       'Reason: it is inside {f}, which web pages can write files to without asking '
       '(a planted CLAUDE.md / AGENTS.md could be loaded).\n'
       'Copy the files to another folder and start there. Rule: {rule}')


def norm(p):
    """Normalize a path for comparison (Git Bash /c/... form, case-insensitive, links resolved)."""
    p = p.strip().strip('"')
    if len(p) >= 3 and p[0] == '/' and p[2] == '/' and p[1].isalpha():
        p = p[1] + ':' + p[2:]
    try:
        p = os.path.realpath(os.path.expandvars(p))
    except OSError:
        p = os.path.abspath(os.path.expandvars(p))
    return os.path.normcase(p).rstrip('\\/')


def forbidden():
    """List of blocked folders. Computed on every call, so a relocated Downloads folder is followed."""
    out = []
    home = os.path.expanduser('~')
    out.append(os.path.join(home, 'Downloads'))
    try:
        k = winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                           r'Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders')
        out.append(winreg.QueryValueEx(k, DOWNLOADS_GUID)[0])
    except OSError:
        pass
    lad = os.environ.get('LOCALAPPDATA') or os.path.join(home, 'AppData', 'Local')
    out += glob.glob(os.path.join(lad, 'Google', 'Chrome*'))
    # Download directories set per Chrome profile
    for pref in glob.glob(os.path.join(lad, 'Google', 'Chrome*', 'User Data', '*', 'Preferences')):
        try:
            with open(pref, encoding='utf-8') as f:
                d = json.load(f).get('download', {}).get('default_directory')
            if d:
                out.append(d)
        except Exception:
            pass
    return sorted({norm(p) for p in out if p})


def hit(cwd):
    """Return the blocked folder that contains cwd, or None."""
    c = norm(cwd)
    for f in forbidden():
        if c == f or c.startswith(f + os.sep):
            return f
    return None


def main():
    rule = os.path.abspath(__file__)
    if len(sys.argv) >= 3 and sys.argv[1] == '--check':
        f = hit(sys.argv[2])
        if f:
            sys.stderr.reconfigure(encoding='utf-8')
            print(MSG.format(cwd=sys.argv[2], f=f, rule=rule), file=sys.stderr)
            sys.exit(2)
        sys.exit(0)

    try:
        data = json.loads(sys.stdin.buffer.read().decode('utf-8', 'replace') or '{}')
    except Exception:
        data = {}
    cwd = data.get('cwd') or os.getcwd()
    f = hit(cwd)
    if not f:
        sys.exit(0)

    # Refusals are returned as exit code 0 + JSON, a format both Claude Code and Codex understand.
    msg = MSG.format(cwd=cwd, f=f, rule=rule)
    ev = data.get('hook_event_name', '')
    if ev == 'PreToolUse':
        out = {'hookSpecificOutput': {'hookEventName': 'PreToolUse',
               'permissionDecision': 'deny', 'permissionDecisionReason': msg}}
    elif ev == 'UserPromptSubmit':
        out = {'decision': 'block', 'reason': msg}
    else:  # SessionStart and others: stop the session
        out = {'continue': False, 'stopReason': msg}
    sys.stdout.reconfigure(encoding='utf-8')
    print(json.dumps(out, ensure_ascii=False))
    sys.exit(0)


if __name__ == '__main__':
    main()
