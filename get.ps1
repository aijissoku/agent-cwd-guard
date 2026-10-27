<#
.SYNOPSIS
  One-line installer for agent-cwd-guard.

  irm https://raw.githubusercontent.com/aijissoku/agent-cwd-guard/main/get.ps1 | iex

  Downloads the latest version to %LOCALAPPDATA%\agent-cwd-guard and runs install.ps1 as administrator
  (a UAC prompt appears if this window is not elevated). Works from Windows PowerShell 5.1,
  but the installer itself needs PowerShell 7 (pwsh).

.PARAMETER NoProfiles
  Do not modify shell profiles (passed to install.ps1).
.PARAMETER Python
  python.exe to use (passed to install.ps1).
#>
param(
    [switch]$NoProfiles,
    [string]$Python
)
$ErrorActionPreference = 'Stop'
$repo = 'aijissoku/agent-cwd-guard'
$dest = Join-Path $env:LOCALAPPDATA 'agent-cwd-guard'

$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $pwsh) { throw 'PowerShell 7 (pwsh) is required. Install it first: winget install Microsoft.PowerShell' }

# Download and extract the latest version (replacing any previous copy)
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('agent-cwd-guard-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $tmp | Out-Null
try {
    $zip = Join-Path $tmp 'src.zip'
    Invoke-WebRequest "https://github.com/$repo/archive/refs/heads/main.zip" -OutFile $zip -UseBasicParsing
    Expand-Archive $zip $tmp
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Move-Item (Join-Path $tmp 'agent-cwd-guard-main') $dest
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "Downloaded to $dest"

$installArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $dest 'install.ps1'))
if ($NoProfiles) { $installArgs += '-NoProfiles' }
if ($Python) { $installArgs += @('-Python', $Python) }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    & $pwsh @installArgs
} else {
    # Run in an elevated window and keep it open so the result can be read.
    # Start-Process joins arguments into one command line, so quote any that contain spaces.
    Write-Host 'Running install.ps1 as administrator (approve the UAC prompt)...'
    $quoted = @('-NoExit') + ($installArgs | ForEach-Object { if ($_ -match ' ') { '"{0}"' -f $_ } else { $_ } })
    Start-Process $pwsh -Verb RunAs -Wait -ArgumentList $quoted
}
Write-Host "Test:      pwsh -File `"$(Join-Path $dest 'test.ps1')`" -Live"
Write-Host "Uninstall: pwsh -File `"$(Join-Path $dest 'uninstall.ps1')`"  (as administrator)"
