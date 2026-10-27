#Requires -Version 7
#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Uninstall agent-cwd-guard. Only what this tool added is removed; other settings are kept.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

# Claude Code
if (Test-Path $ClaudeSettings) {
    $settings = Get-Content $ClaudeSettings -Raw | ConvertFrom-Json -AsHashtable
    Remove-GuardFromClaudeSettings $settings
    if ($settings.Count) { Write-Utf8 $ClaudeSettings ($settings | ConvertTo-Json -Depth 20) } else { Remove-Item $ClaudeSettings }
}

# Codex
if (Test-Path $CodexReq) {
    $t = (Remove-MarkedBlock (Get-Content $CodexReq -Raw)).Trim()
    if ($t) { Write-Utf8 $CodexReq ($t + "`n") } else { Remove-Item $CodexReq }
}

# Profiles: remove the marked block and the lines inserted into existing functions
foreach ($p in $PsAllHosts + $PsCurrentHost + $Bashrc) {
    if (-not (Test-Path $p)) { continue }
    $t = Remove-MarkedBlock (Get-Content $p -Raw)
    $t = [regex]::Replace($t, '(?m)^.*' + [regex]::Escape($LineMark) + '\r?\n', '')
    Write-Utf8 $p $t -Bom:($p -ne $Bashrc)
}

# Script and permissions
Remove-Item $GuardDir -Recurse -Force -ErrorAction SilentlyContinue
foreach ($d in $ClaudeDir, $CodexDir) { if (Test-Path $d) { icacls $d /reset /T /C | Out-Null } }

Write-Host 'Uninstalled (takes effect in new shells).' -ForegroundColor Green
