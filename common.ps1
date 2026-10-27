# Shared definitions for install.ps1 / uninstall.ps1 / test.ps1

$GuardDir       = 'C:\ProgramData\AgentGuard'
$GuardScript    = Join-Path $GuardDir 'cwd_guard.py'
$ClaudeDir      = 'C:\Program Files\ClaudeCode'
$ClaudeSettings = Join-Path $ClaudeDir 'managed-settings.json'
$CodexDir       = 'C:\ProgramData\OpenAI\Codex'
$CodexReq       = Join-Path $CodexDir 'requirements.toml'
$Events         = 'SessionStart', 'UserPromptSubmit', 'PreToolUse'

$BeginMark = '# >>> agent-cwd-guard >>>'
$EndMark   = '# <<< agent-cwd-guard <<<'
$LineMark  = '# agent-cwd-guard'   # marks the single line inserted into existing functions

$docs          = [Environment]::GetFolderPath('MyDocuments')
$PsAllHosts    = @((Join-Path $docs 'PowerShell\profile.ps1'), (Join-Path $docs 'WindowsPowerShell\profile.ps1'))
$PsCurrentHost = @((Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'), (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'))
$Bashrc        = Join-Path $HOME '.bashrc'

function Write-Utf8([string]$Path, [string]$Text, [switch]$Bom) {
    # Profiles are written with a BOM so that Windows PowerShell 5.1 reads them as UTF-8
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($Bom.IsPresent)))
}

function Remove-MarkedBlock([string]$Text) {
    $pattern = '(?s)' + [regex]::Escape($BeginMark) + '.*?' + [regex]::Escape($EndMark) + '\r?\n?'
    return [regex]::Replace($Text, $pattern, '')
}

function Install-ProfileBlock([string]$Path, [string]$Body, [string]$Comment, [switch]$Lf) {
    # Put the marked block at the top of the file, so functions defined later in the profile take precedence
    New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null
    $old = if (Test-Path $Path) { Remove-MarkedBlock (Get-Content $Path -Raw) } else { '' }
    $nl = if ($Lf) { "`n" } else { "`r`n" }
    $block = ($BeginMark + "`n" + $Body.Trim() + "`n" + $EndMark + "`n`n") -replace '\r?\n', $nl
    Write-Utf8 $Path ($block + $old) -Bom:(-not $Lf)
}

function Add-GuardLineToPsFunctions([string]$Path) {
    # Insert the check as the first line of existing claude / codex functions
    if (-not (Test-Path $Path)) { return }
    $t = Get-Content $Path -Raw
    $n = [regex]::Replace($t, '(?m)^(function\s+(claude|codex)\s*\{[ \t]*\r?\n)(?![ \t]*if \(-not \(Test-AgentGuardCwd\)\))',
        { param($m) $m.Groups[1].Value + "    if (-not (Test-AgentGuardCwd)) { return }  $LineMark`r`n" })
    if ($n -ne $t) { Write-Utf8 $Path $n -Bom }
}

function Add-GuardLineToBashFunctions([string]$Path) {
    if (-not (Test-Path $Path)) { return }
    $t = Get-Content $Path -Raw
    $n = [regex]::Replace($t, '(?m)^((claude|codex)\s*\(\)\s*\{[ \t]*\r?\n)(?![ \t]*_agentguard_ok)',
        { param($m) $m.Groups[1].Value + "    _agentguard_ok || return 2  $LineMark`n" })
    if ($n -ne $t) { Write-Utf8 $Path $n }
}

function Remove-GuardFromClaudeSettings($Settings) {
    # Remove only this tool's hooks from managed-settings.json; other hooks are kept
    if (-not $Settings.Contains('hooks')) { return }
    foreach ($ev in @($Settings['hooks'].Keys)) {
        $kept = @($Settings['hooks'][$ev] | Where-Object { -not ($_.hooks | Where-Object { $_.command -like '*cwd_guard.py*' }) })
        if ($kept.Count) { $Settings['hooks'][$ev] = $kept } else { $Settings['hooks'].Remove($ev) }
    }
    if ($Settings['hooks'].Count -eq 0) { $Settings.Remove('hooks') }
}
