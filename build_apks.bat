@echo off
REM =====================================================
REM Limpopo Voice - Universal APK Build Script
REM =====================================================
REM This script builds all APK variants for Android distribution
REM Usage: Run this from the project root directory
REM =====================================================

setlocal enabledelayedexpansion
cd /d "%~dp0"

echo.
echo ========================================
echo Limpopo Voice - Building APK Packages
echo ========================================
echo.

REM Set timestamp for build folder
for /f "tokens=2-4 delims=/ " %%a in ('date /t') do (set mydate=%%c%%a%%b)
for /f "tokens=1-2 delims=/:" %%a in ('time /t') do (set mytime=%%a%%b)

echo [%date% %time%] Starting build...
echo.

REM Clean previous builds
echo [*] Cleaning previous builds...
flutter clean

REM Build Universal APK (all architectures)
echo.
echo [1/4] Building UNIVERSAL APK (all CPU architectures)...
call flutter build apk --release
if errorlevel 1 (
    echo ERROR: Universal APK build failed!
    pause
    exit /b 1
)

REM Build Split APKs by architecture
echo.
echo [2/4] Building split APKs by CPU architecture...
call flutter build apk --release --split-per-abi
if errorlevel 1 (
    echo ERROR: Split APK build failed!
    pause
    exit /b 1
)

REM Build AAB for Play Store
echo.
echo [3/4] Building App Bundle (AAB) for Play Store...
call flutter build appbundle --release
if errorlevel 1 (
    echo ERROR: AAB build failed!
    pause
    exit /b 1
)

REM Copy to distribution folder
echo.
echo [4/4] Organizing distribution packages...

if not exist "distribution_packages" mkdir distribution_packages

REM Clear old packages
del /q distribution_packages\LimpopoVoice-*.apk 2>nul

REM Copy new packages with clear naming
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "distribution_packages\LimpopoVoice-UNIVERSAL-59MB.apk" >nul
copy /Y "build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk" "distribution_packages\LimpopoVoice-32bit-OlderPhones-25MB.apk" >nul
copy /Y "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" "distribution_packages\LimpopoVoice-64bit-NewerPhones-27MB.apk" >nul
copy /Y "build\app\outputs\bundle\release\app-release.aab" "distribution_packages\LimpopoVoice-PlayStore-47MB.aab" >nul

echo.
echo ========================================
echo ✓ BUILD COMPLETE
echo ========================================
echo.

REM Show file sizes
echo Distribution packages ready:
echo.
for %%f in ("distribution_packages\LimpopoVoice-*.apk", "distribution_packages\LimpopoVoice-*.aab") do (
    for /F "usebackq" %%A in ('%%~zf') do (
        set /a size=%%A / 1048576
        echo   ✓ %%~nf (!size! MB^)
    )
)

echo.
echo ========================================
echo Distribution Folder: distribution_packages\
echo ========================================
echo.
echo For OLDER phones (pre-2017): Use 32-bit or UNIVERSAL
echo For NEWER phones (2017+):    Use 64-bit or UNIVERSAL
echo For PLAY STORE:              Use AAB
echo For SIDELOAD (any phone):    Use UNIVERSAL APK
echo.

pause
