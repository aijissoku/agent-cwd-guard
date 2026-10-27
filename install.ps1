#Requires -Version 7
#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Install agent-cwd-guard on this PC (idempotent).

.DESCRIPTION
  1. Copy cwd_guard.py to C:\ProgramData\AgentGuard
  2. Claude Code: add hooks to C:\Program Files\ClaudeCode\managed-settings.json (merged with existing settings)
  3. Codex CLI:   add hooks to C:\ProgramData\OpenAI\Codex\requirements.toml
  4. Make the three folders above writable by administrators and SYSTEM only
  5. Unless -NoProfiles: add the launch-time check to the PowerShell 7 / 5.1 and Git Bash profiles

.PARAMETER Python
  python.exe to use. Auto-detected if omitted.
.PARAMETER NoProfiles
  Do not modify shell profiles.
#>
param(
    [string]$Python,
    [switch]$NoProfiles
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

# ---------- Find Python ----------
if (-not $Python) {
    $Python = (& py -3 -c 'import sys; print(sys.executable)' 2>$null)
    if (-not $Python) { $Python = (Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
}
if (-not $Python -or -not (Test-Path $Python)) { throw 'python.exe not found. Specify it with -Python.' }
$Python = (Resolve-Path $Python).Path
if ($Python -match ' ') {
    # Codex runs hooks through cmd /c on Windows, so use the 8.3 short name for paths with spaces
    $Python = (New-Object -ComObject Scripting.FileSystemObject).GetFile($Python).ShortPath
}
Write-Host "Python: $Python"

# ---------- 1. Deploy the script ----------
New-Item -ItemType Directory -Force $GuardDir, $ClaudeDir, $CodexDir | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'cwd_guard.py') $GuardScript -Force

$cmdClaude = '"{0}" -I "{1}"' -f ($Python -replace '\\', '/'), ($GuardScript -replace '\\', '/')   # Claude Code runs hooks through Git Bash
$cmdCodex  = '{0} -I {1}' -f $Python, $GuardScript                                                 # Codex runs hooks through cmd /c (no quotes)

# ---------- 2. Claude Code ----------
$settings = if (Test-Path $ClaudeSettings) { Get-Content $ClaudeSettings -Raw | ConvertFrom-Json -AsHashtable } else { [ordered]@{} }
if (-not $settings) { $settings = [ordered]@{} }
Remove-GuardFromClaudeSettings $settings
if (-not $settings.Contains('hooks')) { $settings['hooks'] = [ordered]@{} }
$h = [ordered]@{ type = 'command'; command = $cmdClaude; timeout = 10 }
foreach ($ev in $Events) {
    $entry = [ordered]@{}
    if ($ev -eq 'PreToolUse') { $entry['matcher'] = '*' }
    $entry['hooks'] = @($h)
    $settings['hooks'][$ev] = @($settings['hooks'][$ev] | Where-Object { $_ }) + @($entry)
}
Write-Utf8 $ClaudeSettings ($settings | ConvertTo-Json -Depth 20)
Write-Host "Claude: $ClaudeSettings"

# ---------- 3. Codex ----------
$toml = if (Test-Path $CodexReq) { Remove-MarkedBlock (Get-Content $CodexReq -Raw) '#' } else { '' }
if ($toml -match '(?m)^\s*\[+hooks') {
    # TOML is hard to merge safely, so an existing [hooks] section without our markers is left alone
    Write-Warning "$CodexReq already has a [hooks] section; skipped Codex. Merge the hooks by hand."
} else {
    $block = "$BeginMark`n# agent-cwd-guard: refuse the session when the working directory is a blocked folder.`n[hooks]`n"
    foreach ($ev in $Events) {
        $block += "`n[[hooks.$ev]]`n"
        if ($ev -eq 'PreToolUse') { $block += "matcher = `"*`"`n" }
        $block += "[[hooks.$ev.hooks]]`ntype = `"command`"`ncommand = '$cmdCodex'`ntimeout = 10`n"
    }
    $block += "$EndMark`n"
    Write-Utf8 $CodexReq (($toml.TrimEnd() + "`n`n" + $block).TrimStart())
    Write-Host "Codex:  $CodexReq"
}

# ---------- 4. Permissions ----------
foreach ($d in $GuardDir, $ClaudeDir, $CodexDir) {
    # Restrict the folders; files inside inherit the restriction
    icacls $d /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' 'Users:(OI)(CI)RX' | Out-Null
    icacls "$d\*" /reset /T /C | Out-Null
}
Write-Host 'Permissions: writable by administrators and SYSTEM only'

# ---------- 5. Shell profiles ----------
if (-not $NoProfiles) {
    $ps = Get-Content (Join-Path $PSScriptRoot 'profile-snippets\powershell.ps1') -Raw
    $ps = $ps.Replace('__PYTHON__', $Python).Replace('__GUARD__', $GuardScript)
    foreach ($p in $PsAllHosts) { Install-ProfileBlock $p $ps '#' }
    foreach ($p in $PsAllHosts + $PsCurrentHost) { Add-GuardLineToPsFunctions $p }

    $sh = Get-Content (Join-Path $PSScriptRoot 'profile-snippets\bash.sh') -Raw
    $sh = $sh.Replace('__PYTHON__', ($Python -replace '\\', '/')).Replace('__GUARD__', ($GuardScript -replace '\\', '/'))
    Install-ProfileBlock $Bashrc $sh '#' -Lf
    Add-GuardLineToBashFunctions $Bashrc
    Write-Host 'Profiles: launch-time check added (takes effect in new shells)'
}

Write-Host "`nInstalled. To test: pwsh -File `"$(Join-Path $PSScriptRoot 'test.ps1')`"" -ForegroundColor Green
