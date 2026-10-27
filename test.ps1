#Requires -Version 7
<#
.SYNOPSIS
  Test agent-cwd-guard. With -Live, a blocked session is stopped before anything is sent to the model,
  so almost no tokens are used.
.PARAMETER Live
  Actually start claude / codex in the Downloads folder and confirm they are blocked.
#>
param([switch]$Live)
. (Join-Path $PSScriptRoot 'common.ps1')
$py = (Get-Content $ClaudeSettings -Raw | ConvertFrom-Json).hooks.SessionStart[0].hooks[0].command -replace '^"([^"]+)".*', '$1'
$dl = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders').'{374DE290-123F-4565-9164-39C4925E467B}'
$dl = [Environment]::ExpandEnvironmentVariables($dl)
$fail = 0

function Check([string]$Dir, [int]$Expect) {
    & $py -I $GuardScript --check $Dir 2>$null
    $ok = $LASTEXITCODE -eq $Expect
    if (-not $ok) { $script:fail++ }
    '{0}  expected={1} actual={2}  {3}' -f ($(if ($ok) { 'OK ' } else { 'NG ' }), $Expect, $LASTEXITCODE, $Dir)
}

'--- Path checks'
Check $dl 2
Check (Join-Path $dl 'sub\dir') 2
Check ($dl.ToUpper()) 2
Check (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default') 2
Check $HOME 0
Check ($dl + 'X') 0

'--- Hook JSON'
$out = @{ cwd = $dl; hook_event_name = 'UserPromptSubmit' } | ConvertTo-Json | & $py -I $GuardScript
if ($out -match '"decision": "block"') { 'OK  UserPromptSubmit -> block' } else { $fail++; "NG  UserPromptSubmit: $out" }
$out = @{ cwd = $dl; hook_event_name = 'PreToolUse' } | ConvertTo-Json | & $py -I $GuardScript
if ($out -match '"permissionDecision": "deny"') { 'OK  PreToolUse -> deny' } else { $fail++; "NG  PreToolUse: $out" }
$out = @{ cwd = $HOME; hook_event_name = 'UserPromptSubmit' } | ConvertTo-Json | & $py -I $GuardScript
if (-not $out) { 'OK  home -> no output (allowed)' } else { $fail++; "NG  home: $out" }

if ($Live) {
    '--- Live (start in the Downloads folder)'
    Push-Location $dl
    try {
        $c = (Get-Command claude -CommandType Application | Select-Object -First 1).Source
        $r = & $c -p 'reply OK' 2>&1 | Out-String
        if ($r -match 'AgentGuard') { 'OK  claude was blocked' } else { $fail++; "NG  claude: $r" }
        $x = (Get-Command codex -CommandType Application | Where-Object Extension -eq '.cmd' | Select-Object -First 1).Source
        $r = & $x exec --skip-git-repo-check 'reply OK' 2>&1 | Out-String
        if ($r -match 'SessionStart Stopped') { 'OK  codex was blocked' } else { $fail++; "NG  codex: $r" }
    } finally { Pop-Location }
}

if ($fail) { Write-Host "$fail failed" -ForegroundColor Red; exit 1 } else { Write-Host 'All OK' -ForegroundColor Green }
