#!/usr/bin/env python3
"""Reject Web builds with a different libc++ ABI than our supported toolchain."""

from pathlib import Path
import re
import subprocess
import sys


def check_toolchain():
    root = Path(__file__).resolve().parent.parent
    expected = (root / ".emscripten-version").read_text().strip()
    try:
        output = subprocess.check_output(
            ["emcc", "--version"], text=True, stderr=subprocess.STDOUT
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise RuntimeError("Cannot run emcc. Activate the project's Emscripten SDK.") from error
    # A fresh SDK may print sanity-check messages before its version banner.
    version = re.search(r"^emcc .*?\)\s+(\d+\.\d+\.\d+\S*)", output, re.MULTILINE)
    actual = version.group(1) if version else output.strip()
    if actual != expected:
        raise RuntimeError(
            f"Web builds require Emscripten {expected}; found {actual}.\n"
            f"Run: emsdk install {expected} && emsdk activate {expected}\n"
            "Then source emsdk_env.sh and rebuild ThorVG and the extension.\n"
            "Different libc++ versions can compile successfully but fail in the browser."
        )
    print(f"Emscripten {expected}: version check passed")
    return expected


if __name__ == "__main__":
    try:
        check_toolchain()
    except RuntimeError as error:
        sys.exit(str(error))
