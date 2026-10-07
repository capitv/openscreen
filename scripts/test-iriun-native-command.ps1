# Exercise the real build wrapper without running Windows toolchain setup.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$tokens = $null
$parseErrors = $null
$buildScript = Join-Path $PSScriptRoot 'build-iriun-appveyor.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($buildScript, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw "Build script syntax errors: $parseErrors" }
$wrapper = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-Checked'
}, $true)
if ($null -eq $wrapper) { throw 'The actual build wrapper was not found.' }
Invoke-Expression $wrapper.Extent.Text
$shell = @('powershell.exe', 'pwsh.exe', 'pwsh') |
    ForEach-Object { Join-Path $PSHOME $_ } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1
if (-not $shell) { throw 'No child PowerShell executable found.' }

Invoke-Checked $shell @('-NoProfile', '-Command', "[Console]::Error.WriteLine('simulated npm warning'); [Console]::Out.WriteLine('native command succeeded'); exit 0")
if ($ErrorActionPreference -ne 'Stop') { throw 'Error preference was not restored after success.' }
Write-Host 'PASS: stderr warning plus exit 0 succeeds and retains Stop'

$failedAsRequired = $false
try {
    Invoke-Checked $shell @('-NoProfile', '-Command', "[Console]::Error.WriteLine('simulated native failure'); exit 7")
} catch {
    if ($_.Exception.Message -notlike '*exit code 7*') { throw }
    $failedAsRequired = $true
}
if (-not $failedAsRequired) { throw 'Native failure was swallowed.' }
if ($ErrorActionPreference -ne 'Stop') { throw 'Error preference was not restored after failure.' }
Write-Host 'PASS: stderr plus exit 7 fails the build and retains Stop'

$missingAsRequired = $false
try { Invoke-Checked "openscreen-missing-$([guid]::NewGuid()).exe" @() } catch { $missingAsRequired = $true }
if (-not $missingAsRequired) { throw 'Missing executable was silently accepted.' }
Write-Host 'PASS: a missing executable fails before launch'
