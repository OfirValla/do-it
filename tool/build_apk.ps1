<#
.SYNOPSIS
    Builds the Do It Android APK and copies it to dist/ with a versioned name.

.DESCRIPTION
    Runs the full pipeline: dependencies, Drift code generation, static analysis,
    tests and `flutter build apk`. The resulting APK(s) are copied to the output
    directory as do_it-<version>-<variant>.apk and their SHA-256 is printed.

.PARAMETER Mode
    release (default), debug or profile.

.PARAMETER SplitPerAbi
    Produce one smaller APK per CPU architecture instead of a fat APK.

.PARAMETER SkipTests
    Skip `flutter test` (for example on machines that block flutter_tester.exe).

.PARAMETER SkipCodegen
    Skip `dart run build_runner build` when the generated Drift file is current.

.PARAMETER OutputDir
    Where to copy the APK(s). Default: dist

.EXAMPLE
    .\tool\build_apk.ps1
    .\tool\build_apk.ps1 -Mode debug -SkipTests
    .\tool\build_apk.ps1 -SplitPerAbi
#>
[CmdletBinding()]
param(
    [ValidateSet('release', 'debug', 'profile')]
    [string]$Mode = 'release',
    [switch]$SplitPerAbi,
    [switch]$SkipTests,
    [switch]$SkipCodegen,
    [string]$OutputDir = 'dist'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $projectRoot

function Invoke-Step {
    param([string]$Name, [scriptblock]$Command)
    Write-Host ""
    Write-Host "==> $Name" -ForegroundColor Cyan
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'flutter was not found on PATH. Install Flutter and run `flutter doctor`.'
}

$version = (Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
Write-Host "Do It $version - $Mode build" -ForegroundColor Green

Invoke-Step 'flutter pub get' { flutter pub get }

if (-not $SkipCodegen) {
    Invoke-Step 'Drift code generation' { dart run build_runner build }
}

Invoke-Step 'flutter analyze' { flutter analyze }

if (-not $SkipTests) {
    Invoke-Step 'flutter test' { flutter test }
}

$buildArgs = @('build', 'apk', "--$Mode")
if ($SplitPerAbi) { $buildArgs += '--split-per-abi' }
Invoke-Step "flutter $($buildArgs -join ' ')" { flutter @buildArgs }

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$apks = Get-ChildItem -Path 'build/app/outputs/flutter-apk' -Filter "*-$Mode.apk"
if (-not $apks) { throw 'No APK found in build/app/outputs/flutter-apk' }

Write-Host ""
Write-Host "==> Output" -ForegroundColor Cyan
foreach ($apk in $apks) {
    $variant = $apk.BaseName -replace '^app-', ''
    $destination = Join-Path $OutputDir "do_it-$version-$variant.apk"
    Copy-Item -Path $apk.FullName -Destination $destination -Force
    $hash = (Get-FileHash -Path $destination -Algorithm SHA256).Hash.ToLower()
    $sizeMb = [math]::Round($apk.Length / 1MB, 1)
    Write-Host ("{0}  ({1} MB)" -f (Resolve-Path $destination).Path, $sizeMb) -ForegroundColor Green
    Write-Host "  sha256 $hash"
}

Write-Host ""
Write-Host 'Install with: adb install -r <apk>' -ForegroundColor DarkGray
