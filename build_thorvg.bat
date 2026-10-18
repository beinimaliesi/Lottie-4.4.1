@echo off
REM ThorVG Build Script for Windows
REM Builds optimized ThorVG with multi-threading, SIMD, Lottie + embedded PNG support

echo ========================================
echo Building optimized ThorVG library
echo Target: Lottie animations only
echo Optimizations: Multi-threading, SIMD, Partial rendering
echo ========================================
echo.

REM Check for required build tools
where meson >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Meson not found in PATH
    echo.
    echo Installing and adding to PATH...
    python -m pip install --user meson ninja
    
    REM Add Python Scripts to PATH for current session
    set "PATH=%PATH%;%APPDATA%\Python\Python313\Scripts"
    
    echo.
    echo Meson installed. If build still fails, restart your terminal.
    echo.
)

echo Build tools verified: Meson available
echo.

REM Navigate to ThorVG directory
cd thirdparty\thorvg

REM Apply upstream patches (from Godot's vendored thorvg) on a clean checkout.
REM The submodule is pinned to a tag, so patches live in the parent repo and
REM are applied here instead of being committed into the submodule.
REM 0001 removes thorvg's global operator new/delete overrides, which would
REM hijack host-process allocations when statically linked.
set "PATCH_DIR=..\thorvg-upstream-patches"
git apply --check "%PATCH_DIR%\0001-let-delete-be-delete.patch" 2>nul
if %ERRORLEVEL% EQU 0 (
    git apply "%PATCH_DIR%\0001-let-delete-be-delete.patch"
    echo Applied thorvg patch: 0001-let-delete-be-delete.patch
) else (
    git diff --quiet -- src/common/tvgCommon.h
    if ERRORLEVEL 1 echo thorvg patches already applied
)

REM Clean previous build
if exist builddir (
    echo Cleaning previous build directory...
    rmdir /s /q builddir
)

REM Detect CPU core count for parallel compilation. NUMBER_OF_PROCESSORS is
REM always set on Windows; wmic was deprecated/removed in recent Windows 11
REM builds so we no longer rely on it.
if defined NUMBER_OF_PROCESSORS (
    set "CORES=%NUMBER_OF_PROCESSORS%"
) else (
    set "CORES=4"
)

REM Configure build with optimal settings for Lottie rendering
echo Configuring ThorVG build with optimizations...
REM -Ddefault_library=static so the extension .dll links ThorVG into itself
REM instead of requiring thorvg-1.dll alongside. This also drops the
REM transitive VCRUNTIME140_1.dll / MSVCP140.dll / VCOMP140.DLL dependencies
REM that thorvg-1.dll otherwise brings in -- which is what made the
REM extension fail to load in older Godot editors (e.g. 4.4.1) that ship
REM an older bundled MSVC runtime.
REM
REM -Db_vscrt=mt forces ThorVG to use the static C runtime (/MT) so its
REM objects can be linked into the extension .dll, which godot-cpp also
REM builds with /MT. Without this flag meson defaults to /MD and the
REM linker errors out with LNK2038 RuntimeLibrary mismatch.
meson setup builddir ^
  -Dbuildtype=release ^
  -Doptimization=3 ^
  -Db_ndebug=true ^
  -Ddefault_library=static ^
  -Db_vscrt=mt ^
  -Dsimd=true ^
  -Dthreads=true ^
  -Dpartial=true ^
  -Dengines=sw ^
  -Dloaders=lottie,png ^
  -Dbindings=capi ^
  -Dcpp_args="-DTHORVG_THREAD_SUPPORT" ^
  --backend=ninja ^
  --wipe

if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to configure build
    exit /b 1
)

REM Build with all available CPU cores
echo Building ThorVG using %CORES% parallel jobs...
meson compile -C builddir -j %CORES%

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: ThorVG build failed
    echo Check the output above for error details
    echo.
    exit /b 1
)

echo.
echo ========================================
echo ThorVG build completed successfully
echo.
echo Output location: thirdparty\thorvg\builddir\src\
echo Library file: thorvg-1.lib (static library, linked into the extension .dll)
echo.
echo Enabled optimizations:
echo   - Multi-threading: Task scheduler with %CORES% workers
echo   - SIMD instructions: CPU vectorization enabled
echo   - Partial rendering: Smart update optimizations
echo   - Lottie + PNG loaders: JSON animations with embedded images
echo   - Release mode: Maximum compiler optimizations
echo ========================================

echo.
echo Build script completed. Ready to build Godot extension.
