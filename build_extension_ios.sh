#!/usr/bin/env bash
# Build dynamic iOS XCFrameworks from this repository's sources.
# Requires ./build_thorvg_ios.sh first.
# TARGETS: template_debug template_release (default: both)
# VARIANTS: device sim-arm64 sim-x86_64 (default: all)
# MIN_IOS: minimum deployment target (default: 15.0)
# JOBS: parallel compiler jobs (default: 8)
set -euo pipefail

[[ "$(uname -s)" == Darwin ]] || { echo "iOS builds require macOS and Xcode." >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$SCRIPT_DIR/demo/addons/godot_lottie/bin/ios"
BUILD_DIR="$SCRIPT_DIR/build/ios"
TARGETS="${TARGETS:-template_debug template_release}"
VARIANTS="${VARIANTS:-device sim-arm64 sim-x86_64}"
MIN_IOS="${MIN_IOS:-15.0}"
JOBS="${JOBS:-8}"
if command -v scons >/dev/null 2>&1; then
    SCONS=(scons)
else
    SCONS=(python3 -m SCons)
fi

for target in $TARGETS; do
    case "$target" in
        template_debug|template_release) ;;
        *) echo "Unknown target: $target" >&2; exit 1 ;;
    esac
done
for variant in $VARIANTS; do
    case "$variant" in
        device) thorvg_variant=ios-arm64 ;;
        sim-arm64) thorvg_variant=ios-arm64-simulator ;;
        sim-x86_64) thorvg_variant=ios-x86_64-simulator ;;
        *) echo "Unknown variant: $variant" >&2; exit 1 ;;
    esac
    config="$SCRIPT_DIR/thirdparty/thorvg/builddir_$thorvg_variant/config.h"
    [[ -f "$SCRIPT_DIR/thirdparty/thorvg/builddir_$thorvg_variant/src/libthorvg-1.a" ]] || {
        echo "Missing ThorVG $variant. Run build_thorvg_ios.sh first." >&2; exit 1;
    }
    grep -q '^#define THORVG_PNG_LOADER_SUPPORT 1' "$config" || {
        echo "ThorVG $variant must enable the PNG loader." >&2; exit 1;
    }
done

mkdir -p "$BIN_DIR" "$BUILD_DIR"
STAGE="$(mktemp -d "$BUILD_DIR/.ios-build.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cd "$SCRIPT_DIR"
for target in $TARGETS; do
    device_lib=""
    simulator_libs=()
    for variant in $VARIANTS; do
        case "$variant" in
            device) arch=arm64; simulator=no; suffix=arm64 ;;
            sim-arm64) arch=arm64; simulator=yes; suffix=arm64.simulator ;;
            sim-x86_64) arch=x86_64; simulator=yes; suffix=x86_64.simulator ;;
        esac
        "${SCONS[@]}" platform=ios "target=$target" "arch=$arch" \
            "ios_simulator=$simulator" "ios_min_version=$MIN_IOS" -j"$JOBS"
        name="libgodot_lottie.ios.$target.$suffix.dylib"
        produced="$BUILD_DIR/$name"
        [[ -f "$produced" ]] || { echo "Missing artifact: $produced" >&2; exit 1; }
        cp "$produced" "$STAGE/$name"
        if [[ "$simulator" == no ]]; then
            device_lib="$STAGE/$name"
        else
            simulator_libs+=("$STAGE/$name")
        fi
    done
    args=()
    if [[ -n "$device_lib" ]]; then args+=(-library "$device_lib"); fi
    if [[ ${#simulator_libs[@]} -gt 0 ]]; then
        sim_name="libgodot_lottie.ios.$target.simulator.dylib"
        if [[ ${#simulator_libs[@]} -eq 1 ]]; then
            cp "${simulator_libs[0]}" "$STAGE/$sim_name"
        else
            lipo -create "${simulator_libs[@]}" -output "$STAGE/$sim_name"
        fi
        install_name_tool -id "@rpath/$sim_name" "$STAGE/$sim_name"
        args+=(-library "$STAGE/$sim_name")
    fi
    xcf="libgodot_lottie.ios.$target.xcframework"
    xcodebuild -create-xcframework "${args[@]}" -output "$STAGE/$xcf"
    # Partial device builds must not remove previously distributed simulator slices.
    python3 - "$BIN_DIR/$xcf" "$STAGE/$xcf" <<'PY'
import plistlib
import shutil
import sys
from pathlib import Path

previous, output = map(Path, sys.argv[1:])
if not (previous / "Info.plist").exists():
    sys.exit(0)
with (previous / "Info.plist").open("rb") as f:
    old = plistlib.load(f)
with (output / "Info.plist").open("rb") as f:
    new = plistlib.load(f)
def platform(library):
    return library["SupportedPlatform"], library.get("SupportedPlatformVariant", "")
rebuilt = {platform(library) for library in new["AvailableLibraries"]}
for library in old["AvailableLibraries"]:
    if platform(library) in rebuilt:
        continue
    library = dict(library)
    identifier = library["LibraryIdentifier"]
    name = Path(library["LibraryPath"]).with_suffix(".dylib").name
    source = previous / identifier / name
    if not source.is_file():
        raise RuntimeError(f"Rebuild this slice; no existing dynamic library: {source}")
    (output / identifier).mkdir(parents=True)
    shutil.copy2(source, output / identifier / name)
    library["LibraryPath"] = name
    if "BinaryPath" in library:
        library["BinaryPath"] = name
    new["AvailableLibraries"].append(library)
with (output / "Info.plist").open("wb") as f:
    plistlib.dump(new, f, sort_keys=False)
PY
    # Only replace the prior package after every selected slice built successfully.
    rm -rf "$BIN_DIR/$xcf"
    mv "$STAGE/$xcf" "$BIN_DIR/$xcf"
    echo "Built: $BIN_DIR/$xcf"
done
