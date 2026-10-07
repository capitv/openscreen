# Windows toolchain setup runs on AppVeyor, never on the user's computer.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:OS -ne 'Windows_NT' -or $env:APPVEYOR_REPO_NAME -ne 'capitv/openscreen' -or
    $env:APPVEYOR_REPO_BRANCH -ne 'fix/iriun-webcam-compat' -or $env:APPVEYOR_PULL_REQUEST_NUMBER) {
    throw 'This experimental build is restricted to the capitv/openscreen Iriun branch on Windows.'
}

function Invoke-Checked {
    param([string] $Program, [string[]] $StepArguments)
    Write-Host "Running: $Program $($StepArguments -join ' ')"
    # Windows PowerShell 5.1 turns native stderr into ErrorRecords. npm, Rust
    # and CMake also write ordinary warnings/progress there: only the process
    # exit code decides whether the native command failed. Keep Stop everywhere
    # else, and resolve the executable before temporarily changing the preference.
    $application = Get-Command $Program -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $application.Source @StepArguments 2>&1 | ForEach-Object { Write-Host $_.ToString() }
        $stepExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($stepExitCode -ne 0) {
        throw "$Program failed with exit code $stepExitCode"
    }
}

function Get-VerifiedDownload {
    param([string] $Url, [string] $Destination, [string] $Sha256)
    if ($Sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw "Invalid SHA256 for $Url" }
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Destination
    if ((Get-FileHash -Algorithm SHA256 $Destination).Hash -ne $Sha256) {
        throw "SHA256 mismatch for $Url"
    }
}

function ConvertTo-DownloadText {
    param([object] $Content)
    # Windows PowerShell exposes application/octet-stream as byte[], including
    # Rust's textual .sha256 response. Do not call string methods on each byte.
    if ($Content -is [byte[]]) { return [Text.Encoding]::UTF8.GetString($Content) }
    return [string] $Content
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$toolRoot = 'C:\osc-tools'
New-Item -ItemType Directory -Force $toolRoot | Out-Null

# AppVeyor's image does not carry the exact Node version from .nvmrc.
$nodeVersion = (Get-Content .nvmrc -Raw).Trim().TrimStart('v')
$nodeAsset = "node-v$nodeVersion-win-x64.zip"
$nodeBase = "https://nodejs.org/dist/v$nodeVersion"
$nodeResponse = Invoke-WebRequest -UseBasicParsing -Uri "$nodeBase/SHASUMS256.txt"
$nodeChecksums = ConvertTo-DownloadText $nodeResponse.Content
$nodeChecksumLine = @($nodeChecksums -split "`n" | Where-Object { $_.Trim().EndsWith("  $nodeAsset") })
if ($nodeChecksumLine.Count -ne 1) { throw "Missing unique checksum for $nodeAsset" }
Get-VerifiedDownload "$nodeBase/$nodeAsset" "$toolRoot/$nodeAsset" ($nodeChecksumLine[0] -split '\s+')[0]
Expand-Archive -Path "$toolRoot/$nodeAsset" -DestinationPath $toolRoot -Force
$nodeRoot = "$toolRoot\node-v$nodeVersion-win-x64"
$env:PATH = "$nodeRoot;$env:PATH"
Invoke-Checked 'node.exe' @('--version')
Invoke-Checked 'npm.cmd' @('install', '--global', '--prefix', $nodeRoot, 'npm@10.9.4')
if ((& npm.cmd --version) -ne '10.9.4' -or $LASTEXITCODE -ne 0) { throw 'The pinned npm version was not activated.' }
Invoke-Checked 'npm.cmd' @('ci')

Invoke-Checked 'cmake.exe' @('--version')
Invoke-Checked 'ninja.exe' @('--version')
if (-not (Test-Path 'C:\Program Files\LLVM\bin\libclang.dll')) {
    throw 'The Windows image is missing LLVM/libclang, required by the compositor.'
}
$gitBash = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path $gitBash)) { throw 'The Windows image is missing Git Bash.' }

$rustupExe = Join-Path $env:USERPROFILE '.cargo\bin\rustup.exe'
if (-not (Test-Path $rustupExe)) {
    $rustupUrl = 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe'
    $rustupResponse = Invoke-WebRequest -UseBasicParsing -Uri "$rustupUrl.sha256"
    $rustupChecksum = ConvertTo-DownloadText $rustupResponse.Content
    $rustupSha = ($rustupChecksum.Trim() -split '\s+')[0]
    Get-VerifiedDownload $rustupUrl "$toolRoot/rustup-init.exe" $rustupSha
    Invoke-Checked "$toolRoot/rustup-init.exe" @('-y', '--profile', 'minimal', '--default-toolchain', 'stable')
} else {
    Invoke-Checked $rustupExe @('update', 'stable', '--no-self-update')
    Invoke-Checked $rustupExe @('default', 'stable')
}
$env:PATH = "$(Join-Path $env:USERPROFILE '.cargo\bin');$env:PATH"
Invoke-Checked 'cargo.exe' @('--version')

# Same prebuilt LunarG SDK as build-whisper-stt.yml; no CPU-only shortcut.
$sdkVersion = '1.4.304.1'
$sdkAsset = "VulkanSDK-$sdkVersion-Installer.exe"
$sdkResponse = Invoke-WebRequest -UseBasicParsing -Uri "https://sdk.lunarg.com/sdk/sha/$sdkVersion/windows/$sdkAsset.json"
$sdkChecksum = ConvertTo-DownloadText $sdkResponse.Content
$sdkSha = ($sdkChecksum | ConvertFrom-Json).sha
Get-VerifiedDownload "https://sdk.lunarg.com/sdk/download/$sdkVersion/windows/$sdkAsset" "$toolRoot/$sdkAsset" $sdkSha
$env:VULKAN_SDK = "C:\VulkanSDK\$sdkVersion"
$sdkInstaller = Start-Process -FilePath "$toolRoot/$sdkAsset" -ArgumentList @(
    '--root', $env:VULKAN_SDK, '--accept-licenses', '--default-answer', '--confirm-command', 'install'
) -Wait -PassThru
if ($sdkInstaller.ExitCode -ne 0) { throw "Vulkan SDK installer failed: $($sdkInstaller.ExitCode)" }
if (-not (Test-Path "$env:VULKAN_SDK\Bin\glslc.exe")) { throw 'Vulkan shader compiler was not installed.' }
$env:PATH = "$env:VULKAN_SDK\Bin;$env:PATH"

# The SDK's Windows installer omits the SPIRV-Headers CMake package. Install
# the matching Khronos headers directly, avoiding the image's old vcpkg ports.
$headersArchive = "$toolRoot/spirv-headers.zip"
Get-VerifiedDownload 'https://github.com/KhronosGroup/SPIRV-Headers/archive/refs/tags/vulkan-sdk-1.4.304.1.zip' $headersArchive '87a95704149313f20a078c9483b7ddf64f48df3187f64455d68e861277b5353d'
Expand-Archive -Path $headersArchive -DestinationPath $toolRoot -Force
$headersSource = "$toolRoot/SPIRV-Headers-vulkan-sdk-1.4.304.1"
$headersBuild = "$toolRoot/spirv-build"
$headersPrefix = "$toolRoot/spirv-installed"
Invoke-Checked 'cmake.exe' @('-S', $headersSource, '-B', $headersBuild, '-G', 'Visual Studio 17 2022', '-A', 'x64', "-DCMAKE_INSTALL_PREFIX=$headersPrefix")
Invoke-Checked 'cmake.exe' @('--build', $headersBuild, '--config', 'Release')
Invoke-Checked 'cmake.exe' @('--install', $headersBuild, '--config', 'Release')
$env:CMAKE_PREFIX_PATH = $headersPrefix
$env:CMAKE_GENERATOR = 'Visual Studio 17 2022'
$env:CMAKE_GENERATOR_PLATFORM = 'x64'
Invoke-Checked $gitBash @('scripts/build-whisper-stt.sh')
# The capture script explicitly selects Ninja, so clear the VS generator hint.
Remove-Item Env:CMAKE_GENERATOR, Env:CMAKE_GENERATOR_PLATFORM

Invoke-Checked 'npx.cmd' @('tsc', '--noEmit')
Invoke-Checked 'npx.cmd' @('tsc', '-p', 'tsconfig.test.json', '--noEmit')
Invoke-Checked 'npm.cmd' @('run', 'build:native:win')
Invoke-Checked 'npm.cmd' @('run', 'fetch:ffmpeg')
Invoke-Checked 'npm.cmd' @('run', 'fetch:onnxruntime')
Invoke-Checked 'npm.cmd' @('run', 'stage:vcomp')
Invoke-Checked 'npm.cmd' @('run', 'build:native:compositor')
Invoke-Checked 'npm.cmd' @('run', 'build-vite')
Invoke-Checked 'npx.cmd' @('electron-builder', '--config', 'electron-builder.iriun.json5', '--win', '--x64', '--dir', '--publish', 'never', '--config.npmRebuild=false')
