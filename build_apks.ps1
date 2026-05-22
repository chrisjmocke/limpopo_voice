# Let's Talk - PowerShell Build Script
# Builds all APK variants for Android distribution
# Usage: .\build_apks.ps1

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Let's Talk - Building APK Packages" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[*] Build started at $(Get-Date)" -ForegroundColor Yellow
Write-Host "[*] Cleaning previous builds..." -ForegroundColor Yellow
flutter clean

Write-Host ""
Write-Host "[1/4] Building UNIVERSAL APK (all CPU architectures)..." -ForegroundColor Cyan
flutter build apk --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Universal APK build failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[2/4] Building split APKs by CPU architecture..." -ForegroundColor Cyan
flutter build apk --release --split-per-abi
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Split APK build failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[3/4] Building App Bundle (AAB) for Play Store..." -ForegroundColor Cyan
flutter build appbundle --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: AAB build failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[4/4] Organizing distribution packages..." -ForegroundColor Cyan

$distPath = "distribution_packages"
if (!(Test-Path $distPath)) {
    New-Item -ItemType Directory -Path $distPath -Force | Out-Null
}

Write-Host "[*] Copying distribution files..." -ForegroundColor Yellow
Copy-Item -Path "build\app\outputs\flutter-apk\app-release.apk" -Destination "$distPath\LetsTalk-UNIVERSAL-59MB.apk" -Force
Copy-Item -Path "build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk" -Destination "$distPath\LetsTalk-32bit-OlderPhones-25MB.apk" -Force
Copy-Item -Path "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" -Destination "$distPath\LetsTalk-64bit-NewerPhones-27MB.apk" -Force
Copy-Item -Path "build\app\outputs\bundle\release\app-release.aab" -Destination "$distPath\LetsTalk-PlayStore-47MB.aab" -Force

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "BUILD COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

Write-Host "Distribution packages ready:" -ForegroundColor Cyan
Write-Host ""
Get-ChildItem "$distPath\LetsTalk-*.apk", "$distPath\LetsTalk-*.aab" -ErrorAction SilentlyContinue | ForEach-Object {
    $sizeMB = [math]::Round($_.Length / 1MB, 1)
    Write-Host "  OK: $($_.Name) ($sizeMB MB)" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Distribution Folder: $distPath" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "For OLDER phones (pre-2017): Use 32-bit or UNIVERSAL" -ForegroundColor Yellow
Write-Host "For NEWER phones (2017+):    Use 64-bit or UNIVERSAL" -ForegroundColor Yellow
Write-Host "For PLAY STORE:              Use AAB" -ForegroundColor Yellow
Write-Host "For SIDELOAD (any phone):    Use UNIVERSAL APK" -ForegroundColor Yellow
Write-Host ""
