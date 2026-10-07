# AppVeyor calls this only after the packaged STT/compositor/Studio tests pass.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$packageDir = 'release/iriun-experimental/win-unpacked'
$commit = $env:APPVEYOR_REPO_COMMIT
if ($env:APPVEYOR_REPO_NAME -ne 'capitv/openscreen' -or $commit -notmatch '^[a-f0-9]{40}$') {
    throw 'Missing fork/commit provenance for the experimental package.'
}
@'
@echo off
cd /d "%~dp0"
start "" "OpenScreen Iriun Experimental.exe" --user-data-dir="%~dp0data"
'@ | Set-Content -Encoding ascii "$packageDir/Abrir-OpenScreen-Iriun.cmd"
@'
Experimental Windows x64 build. Compatibility with Iriun is not confirmed.
Extract this ZIP to a writable folder and run Abrir-OpenScreen-Iriun.cmd.
This is not an installer; projects/settings/recordings stay in the data folder here.
Close other OpenScreen and camera-preview applications before testing the webcam.
After a failed attempt use tray > Save Diagnostics and retain the diagnostic bundle.
This test build is unsigned. No GitHub release is published.
'@ | Set-Content -Encoding utf8 "$packageDir/LEIA-ME.txt"
@{
    repository = $env:APPVEYOR_REPO_NAME
    commit = $commit
    provider = 'AppVeyor'
    build = $env:APPVEYOR_BUILD_ID
    job = $env:APPVEYOR_JOB_ID
    iriunDeviceTest = 'not performed'
} | ConvertTo-Json | Set-Content -Encoding utf8 "$packageDir/build-provenance.json"
$zip = "release/iriun-experimental/OpenScreen-Iriun-Experimental-Windows-x64-$commit.zip"
Compress-Archive -Path "$packageDir/*" -DestinationPath $zip
Get-FileHash -Algorithm SHA256 $zip | Format-List
