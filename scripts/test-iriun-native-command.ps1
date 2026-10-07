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

# AppVeyor carries its own Node in addition to the pinned portable Node.
# Get-Command -CommandType Application can return both: launch the first PATH
# match, never a space-joined list of executable paths.
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "openscreen-native-path-$([guid]::NewGuid())"
$firstDir = Join-Path $testRoot 'first'
$secondDir = Join-Path $testRoot 'second'
$previousPath = $env:PATH
try {
    New-Item -ItemType Directory -Path $firstDir, $secondDir | Out-Null
    if ($env:OS -eq 'Windows_NT') {
        $shadowName = 'openscreen-shadowed-native.cmd'
        Set-Content -Encoding ascii (Join-Path $firstDir $shadowName) "@echo off`r`necho first native`r`nexit /b 0"
        Set-Content -Encoding ascii (Join-Path $secondDir $shadowName) "@echo off`r`nexit /b 7"
    } else {
        $shadowName = 'openscreen-shadowed-native'
        Set-Content -Encoding ascii (Join-Path $firstDir $shadowName) "#!/bin/sh`necho first native`nexit 0"
        Set-Content -Encoding ascii (Join-Path $secondDir $shadowName) "#!/bin/sh`nexit 7"
        Invoke-Checked '/bin/chmod' @('+x', (Join-Path $firstDir $shadowName), (Join-Path $secondDir $shadowName))
    }
    $env:PATH = @($firstDir, $secondDir, $previousPath) -join [IO.Path]::PathSeparator
    if (@(Get-Command $shadowName -CommandType Application).Count -ne 2) { throw 'Duplicate PATH fixture was not created.' }
    Invoke-Checked $shadowName @()
    Write-Host 'PASS: duplicate executables resolve to the first PATH match'
} finally {
    $env:PATH = $previousPath
    Remove-Item -Recurse -Force $testRoot
}
