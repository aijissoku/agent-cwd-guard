# agent-cwd-guard: do not start claude / codex in Downloads or Chrome's data folders.
# install.ps1 fills in the paths and inserts this block at the top of the profile.
function Test-AgentGuardCwd {
    & '__PYTHON__' -I '__GUARD__' --check (Get-Location).ProviderPath
    return ($LASTEXITCODE -ne 2)
}
# Default wrappers. If the profile defines its own claude / codex functions later,
# install.ps1 also inserts the check as the first line of those functions.
function claude {
    if (-not (Test-AgentGuardCwd)) { return }
    $exe = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    & $exe.Source @args
}
function codex {
    if (-not (Test-AgentGuardCwd)) { return }
    $exe = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.exe', '.cmd' } | Select-Object -First 1
    & $exe.Source @args
}
