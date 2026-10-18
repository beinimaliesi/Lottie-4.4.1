@echo off
REM ThorVG Android Build Script (Windows host)
REM Cross-compiles ThorVG for Android arm64-v8a + x86_64 using NDK r25+.
REM
REM Required:
REM   ANDROID_NDK_ROOT (or ANDROID_NDK_HOME) -- path to your NDK install
REM
REM Optional:
REM   API     -- Android API level (default 24, the Godot 4.3+ minimum)
REM   ABIS    -- space-separated list (default "arm64 x86_64")
REM
REM Outputs:
REM   thirdparty\thorvg\builddir_android_arm64\src\libthorvg-1.a
REM   thirdparty\thorvg\builddir_android_x86_64\src\libthorvg-1.a

setlocal enableextensions

REM ---- Resolve NDK -------------------------------------------------------

if "%ANDROID_NDK_ROOT%"=="" if not "%ANDROID_NDK_HOME%"=="" set "ANDROID_NDK_ROOT=%ANDROID_NDK_HOME%"

if "%ANDROID_NDK_ROOT%"=="" (
    echo ERROR: ANDROID_NDK_ROOT ^(or ANDROID_NDK_HOME^) is not set.
    echo.
    echo Point it at your NDK install, for example:
    echo   set "ANDROID_NDK_ROOT=C:\Android\sdk\ndk\26.3.11579264"
    exit /b 1
)

if not exist "%ANDROID_NDK_ROOT%" (
    echo ERROR: ANDROID_NDK_ROOT="%ANDROID_NDK_ROOT%" does not exist.
    exit /b 1
)

set "HOST_TAG=windows-x86_64"
if "%API%"=="" set "API=24"
if "%ABIS%"=="" set "ABIS=arm64 x86_64"

set "TOOLCHAIN_BIN=%ANDROID_NDK_ROOT%\toolchains\llvm\prebuilt\%HOST_TAG%\bin"
if not exist "%TOOLCHAIN_BIN%" (
    echo ERROR: NDK prebuilt toolchain not found at:
    echo        %TOOLCHAIN_BIN%
    echo        ^(Wrong NDK version or wrong host tag?^)
    exit /b 1
)

REM ---- Resolve meson + ninja --------------------------------------------
REM Always prepend the pip --user Scripts dir so meson.exe and ninja.exe
REM (installed via `pip install --user meson ninja`) are findable. The glob
REM is two-step because cmd's `for /d` only expands wildcards in the LAST
REM path component -- `Python*\Scripts` in a single glob silently matches
REM nothing.

for /d %%P in ("%APPDATA%\Python\Python*") do if exist "%%P\Scripts" set "PATH=%%P\Scripts;%PATH%"

set "MESON=meson"
where meson >nul 2>&1
if errorlevel 1 set "MESON=python -m mesonbuild.mesonmain"

%MESON% --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: meson not found.
    echo        Install with: python -m pip install --user meson ninja
    exit /b 1
)
echo Using meson: %MESON%

where ninja >nul 2>&1
if errorlevel 1 (
    echo ERROR: ninja not found in PATH.
    echo        Install with: python -m pip install --user ninja
    exit /b 1
)

REM ---- Validate ThorVG submodule ----------------------------------------

set "SCRIPT_DIR=%~dp0"
set "THORVG_DIR=%SCRIPT_DIR%thirdparty\thorvg"

if not exist "%THORVG_DIR%" (
    echo ERROR: ThorVG submodule not found at %THORVG_DIR%
    echo        Run: git submodule update --init --recursive
    exit /b 1
)

REM Apply upstream patches (from Godot's vendored thorvg) on a clean checkout.
REM The submodule is pinned to a tag, so patches live in the parent repo and
REM are applied here instead of being committed into the submodule.
REM 0001 removes thorvg's global operator new/delete overrides, which would
REM hijack host-process allocations when statically linked.
set "PATCH_DIR=%SCRIPT_DIR%thirdparty\thorvg-upstream-patches"
pushd "%THORVG_DIR%"
git apply --check "%PATCH_DIR%\0001-let-delete-be-delete.patch" 2>nul
if %ERRORLEVEL% EQU 0 (
    git apply "%PATCH_DIR%\0001-let-delete-be-delete.patch"
    echo Applied thorvg patch: 0001-let-delete-be-delete.patch
) else (
    git diff --quiet -- src/common/tvgCommon.h
    if ERRORLEVEL 1 echo thorvg patches already applied
)
popd

REM ---- Build per ABI -----------------------------------------------------

for %%A in (%ABIS%) do (
    call :build_for_abi %%A
    if errorlevel 1 exit /b 1
)

echo.
echo === ThorVG Android build complete ===
for %%A in (%ABIS%) do (
    set "LIB=%THORVG_DIR%\builddir_android_%%A\src\libthorvg-1.a"
    if exist "%THORVG_DIR%\builddir_android_%%A\src\libthorvg-1.a" (
        echo   %%A: %THORVG_DIR%\builddir_android_%%A\src\libthorvg-1.a
    ) else (
        echo   %%A: MISSING
    )
)

echo.
echo Next: build the Godot extension per ABI, for example
echo   python -m SCons platform=android target=template_release arch=arm64
echo   python -m SCons platform=android target=template_release arch=x86_64

endlocal
exit /b 0


REM ---- Subroutine --------------------------------------------------------

:build_for_abi
set "ABI=%~1"
if "%ABI%"=="arm64" (
    set "TRIPLE=aarch64"
    set "CPU_FAMILY=aarch64"
) else if "%ABI%"=="x86_64" (
    set "TRIPLE=x86_64"
    set "CPU_FAMILY=x86_64"
) else if "%ABI%"=="armv7" (
    set "TRIPLE=armv7a"
    set "CPU_FAMILY=arm"
) else if "%ABI%"=="x86" (
    set "TRIPLE=i686"
    set "CPU_FAMILY=x86"
) else (
    echo ERROR: unknown ABI '%ABI%'
    exit /b 1
)

set "BUILDDIR_NAME=builddir_android_%ABI%"
set "BUILDDIR=%THORVG_DIR%\%BUILDDIR_NAME%"
set "CROSSFILE=%BUILDDIR%\.cross.ini"

echo.
echo === ThorVG %ABI% (API %API%, host %HOST_TAG%) ===

if exist "%BUILDDIR%" rmdir /s /q "%BUILDDIR%"
mkdir "%BUILDDIR%"

REM Generate cross-file. .cmd suffix on clang wrappers and .exe on llvm-* are
REM specific to the Windows-prebuilt NDK toolchain.
>  "%CROSSFILE%" echo # Auto-generated by build_thorvg_android.bat -- do not edit by hand.
>> "%CROSSFILE%" echo [binaries]
>> "%CROSSFILE%" echo c = '%TOOLCHAIN_BIN:\=/%/%TRIPLE%-linux-android%API%-clang.cmd'
>> "%CROSSFILE%" echo cpp = '%TOOLCHAIN_BIN:\=/%/%TRIPLE%-linux-android%API%-clang++.cmd'
>> "%CROSSFILE%" echo ar = '%TOOLCHAIN_BIN:\=/%/llvm-ar.exe'
>> "%CROSSFILE%" echo strip = '%TOOLCHAIN_BIN:\=/%/llvm-strip.exe'
>> "%CROSSFILE%" echo pkg-config = 'false'
>> "%CROSSFILE%" echo.
>> "%CROSSFILE%" echo [host_machine]
>> "%CROSSFILE%" echo system = 'android'
>> "%CROSSFILE%" echo cpu_family = '%CPU_FAMILY%'
>> "%CROSSFILE%" echo cpu = '%CPU_FAMILY%'
>> "%CROSSFILE%" echo endian = 'little'

REM NOTE: -Dthreads=false on Android. ThorVG's threaded task scheduler
REM interacts badly with the Android pthread runtime in some versions and
REM causes hangs / crashes when the extension is loaded inside a Godot
REM Android app. Without threads ThorVG renders single-threaded but stably.
pushd "%THORVG_DIR%"
%MESON% setup "%BUILDDIR_NAME%" ^
    --cross-file "%CROSSFILE%" ^
    -Dbuildtype=release -Doptimization=3 -Db_ndebug=true ^
    -Ddefault_library=static ^
    -Dsimd=true -Dthreads=false -Dpartial=true ^
    -Dengines=sw -Dloaders=lottie,png -Dbindings=capi ^
    -Dtests=false ^
    --backend=ninja
if errorlevel 1 (
    popd
    exit /b 1
)
%MESON% compile -C "%BUILDDIR_NAME%"
if errorlevel 1 (
    popd
    exit /b 1
)
popd

exit /b 0
