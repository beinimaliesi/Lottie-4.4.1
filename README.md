# unofficial Lottie-godot plugin

High-performance Lottie animation rendering for Godot Engine 4.7+ using optimized ThorVG backend.

iOS build, artifact distribution, and packed-resource playback regression: [BUILD_IOS.md](BUILD_IOS.md).

![ThorVG Godot Demo](thor-lottie.gif)

*Lottie animations running at 146 FPS with ThorVG's software render optimized multi-threaded rendering*

Note: this is an integration demo for personal use, so features may fail/be incomplete and may not perform as expected.

## Features

- **Ready-to-use nodes**: `LottieAnimation` (2D / `Node2D`) and `LottieAnimation3D` (3D / `Sprite3D`) — drop-in nodes for seamless Lottie integration in 2D, UI, and 3D scenes
- **3D support**: `LottieAnimation3D` plays Lottie on a quad in 3D space with full `Sprite3D` features (billboard, alpha-cut, pixel size, double-sided, modulate)
- **Hybrid CPU-GPU rendering**: ThorVG rasterizes vector data to RGBA8888 format in CPU memory, then converts to RGB texture for Godot's draw system
- **Multi-threaded rendering**: Parallel processing using all available CPU cores
- **SIMD optimizations**: AVX/SSE (x86/x64) or NEON (ARM) vectorization
- **Smart rendering**: Automatic partial rendering optimizations
- **Lottie-focused**: Optimized build with only necessary loaders
- **Cross-platform**: Windows, Linux, and macOS support

## Quick Demo

**Want to test without building?** The `demo/` folder contains a ready-to-run Godot project with **pre-built binaries for Windows x64**:

1. Open `demo/project.godot` in Godot Engine 4.7+
2. **Enable the plugin**: Go to Project → Project Settings → Plugins and enable "Godot Lottie"
3. Run immediately - no compilation required!
4. Test multiple Lottie animations and performance demos

> **Note**: For Linux and macOS, you'll need to build the extension first (see Installation section below).

## Prerequisites

- **Python 3.7+** with pip
- **Git**
- **C++ Compiler**:
  - Windows: Visual Studio 2019+ or Build Tools
  - Linux: GCC 8+ or Clang 10+
  - macOS: Xcode Command Line Tools

## Installation

### 1. Clone Repository

```bash
git clone https://github.com/Kyooz/thorvg-godot.git
cd thorvg-godot
git submodule update --init --recursive
```

### 2. Install Build Dependencies

**From the project root directory (`thorvg-godot/`):**

**All platforms:**
```bash
pip install meson ninja
```

> **Note**: On Windows, Meson and Ninja will be automatically added to your PATH by the build script if not already installed.

### 3. Build ThorVG

**From the project root directory (`thorvg-godot/`):**

**Option A: Automated Build (Recommended)**

**Windows:**
```cmd
build_thorvg.bat
```

**Linux/macOS:**
```bash
./build_thorvg.sh
```

**Option B: Manual Build (ThorVG Standard Process)**

If you prefer to build ThorVG manually with custom options.

**From the project root directory (`thorvg-godot/`):**

**Windows:**
```bash
cd thirdparty/thorvg
python -m meson setup builddir -Dbuildtype=release -Dsimd=true -Dthreads=true -Dloaders=lottie -Dbindings=capi
python -m meson compile -C builddir
cd ../..
```

**Linux/macOS:**
```bash
cd thirdparty/thorvg
python3 -m meson setup builddir -Dbuildtype=release -Ddefault_library=static -Dsimd=true -Dthreads=true -Dloaders=lottie -Dbindings=capi
python3 -m meson compile -C builddir
cd ../..
```

**Additional ThorVG build options:**

The automated scripts already include optimal settings. For manual builds, you can customize with these flags:

- `-Dengines=sw` — Software renderer only (already enabled)
- `-Dbindings=capi` — C API bindings (required, already enabled)
- `-Ddefault_library=static` — Static library build (Linux/macOS default)
- `-Ddefault_library=shared` — Shared library build (Windows default)
- `-Dtests=false` — Disable tests and examples
- `-Dpartial=true` — Enable partial rendering optimizations (already enabled)
- `-Doptimization=3` — Maximum optimization level (already enabled)

**Example custom build:**

For development/debugging, you can build with custom options:

```bash
cd thirdparty/thorvg

# Step 1: Configure build with custom options
python3 -m meson setup builddir \
    -Dbuildtype=debugoptimized \
    -Ddefault_library=static \
    -Dsimd=true \
    -Dthreads=true \
    -Dloaders=lottie \
    -Dbindings=capi

# Step 2: Compile the library
python3 -m meson compile -C builddir

cd ../..
```

### 4. Build Godot Extension

**From the project root directory (`thorvg-godot/`):**

```bash
# Windows
python -m SCons platform=windows target=template_debug
python -m SCons platform=windows target=template_release

# Linux
python -m SCons platform=linux target=template_debug
python -m SCons platform=linux target=template_release

# macOS
python -m SCons platform=macos target=template_debug
python -m SCons platform=macos target=template_release
```

> **Note**: On Windows, the build automatically copies `thorvg-1.dll` to the addon's bin directory. Linux and macOS use static linking and don't require runtime libraries.

### Web: single-threaded and threaded variants

Use Emscripten **4.0.20** to match the Godot 4.7.2 official Web templates
(including their C++ standard library ABI). Activate that SDK and install
Meson, Ninja and SCons.

The version is pinned in `.emscripten-version`; both the ThorVG script
and SCons reject a different SDK. When switching SDKs, clean the old Web
objects as described in [BUILDING.md](BUILDING.md#63-build-the-extension-for-web).
Then run:

```bash
./build_thorvg_web.sh
for threads in no yes; do
    for target in template_debug template_release; do
        scons platform=web arch=wasm32 target=$target threads=$threads
    done
done
```

The ThorVG script builds `build_wasm_nothreads` and `build_wasm_threads`
separately. Set `WEB_VARIANTS=nothreads` or `WEB_VARIANTS=threads` to build
only one. The threaded library uses `-pthread`; ThorVG's internal worker
pool stays disabled in both variants, preserving the existing Web rendering
behavior.

The extension produces four WASM files: debug/release with `.nothreads.wasm`
and debug/release with `.wasm` (no `.threads` suffix). The `.gdextension`
selects the matching library using feature tags; the `nothreads` entries
must precede the generic Web entries.

Enable **Extensions Support** in the Godot Web export preset and select
**Thread Support** as needed. Build both variants before distributing the
addon. Include `*.lottie` in the export preset's non-resource file filter
when using dotLottie archives. Use `;` for comments in `.gdextension` files
(Godot ConfigFile syntax); `#` can corrupt the following library key.
This supports either export mode; it does not implement browser-time
automatic fallback between two exported games. The CI Web job builds both
thread modes for the selected debug/release targets.

## Build Configuration

### ThorVG Optimizations

The build system configures ThorVG with the following optimizations:

- **SIMD**: Automatic detection and enablement of CPU vectorization
- **Multi-threading**: Task scheduler with configurable worker threads
- **Partial rendering**: Smart rendering optimizations
- **Lottie loader only**: Minimal build excluding unnecessary formats
- **Release mode**: Maximum compiler optimizations

### Rendering Pipeline

The integration uses a hybrid CPU-GPU rendering approach:

1. **Vector Processing**: ThorVG parses Lottie JSON and builds internal vector representation
2. **CPU Rasterization**: ThorVG software renderer rasterizes vectors to ARGB pixel buffer using CPU with SIMD optimizations
3. **Format Conversion**: ARGB data is converted to RGBA format via optimized SIMD routines (SSSE3/NEON)
4. **GPU Upload**: RGBA texture data is uploaded to Godot's rendering system via `ImageTexture`
5. **GPU Compositing**: Godot handles final compositing, blending, and display using GPU shaders

This approach leverages ThorVG's optimized CPU vector processing while maintaining compatibility with Godot's rendering pipeline.

### Supported Platforms

| Platform | Architecture | ThorVG Library | Compiler | Status |
|----------|-------------|----------------|----------|---------|
| Windows  | x86_64      | thorvg-1.dll (shared) | MSVC | ✓ Tested |
| Linux    | x86_64      | libthorvg.a (static) | GCC/Clang| ⚠ Needs testing |
| macOS    | x86_64/ARM64| libthorvg.a (static) | Clang | ⚠ Needs testing |

## Project Structure

```
thorvg-godot/
├── build_thorvg.bat         # Windows build script
├── build_thorvg.sh          # Linux/macOS build script  
├── src/                       # Extension source code
│   ├── lottie_animation.cpp    # 2D animation node (Node2D)
│   ├── lottie_animation.h      # 2D animation header
│   ├── lottie_animation_3d.cpp # 3D animation node (Sprite3D)
│   ├── lottie_animation_3d.h   # 3D animation header
│   ├── lottie_common.h         # Shared node-agnostic helpers
│   └── register_types.cpp      # Godot registration
├── demo/                    # Example project with plugin
│   └── addons/
│       └── godot_lottie/    # ← Plugin folder to copy to your project
└── thirdparty/              # Third-party dependencies
    ├── godot-cpp/           # Godot C++ bindings
    └── thorvg/              # ThorVG vector graphics library
```

## Usage

1. **Copy the plugin**: Copy the `demo/addons/godot_lottie/` folder to your Godot project's `addons/` directory
2. **Enable the plugin**: Go to Project → Project Settings → Plugins and enable "Godot Lottie"
3. **Add a Lottie node**: Add a `LottieAnimation` node to a 2D/UI scene, or a `LottieAnimation3D` node to a 3D scene
4. **Set animation path**: Set the `animation_path` property to your Lottie `.json` or `.lottie` file

For 3D, `LottieAnimation3D` extends `Sprite3D`, so you also get `billboard`,
`alpha_cut`, `pixel_size`, `double_sided` and the rest of the `Sprite3D`
inspector for free. See [API.md](API.md) for the full 3D node reference.

## API Reference

Detailed API documentation for the provided nodes and resources is available in this repository. It includes the `LottieAnimation` node reference (properties, methods, signals) and usage examples in GDScript.

See: **[API.md](API.md)** for a complete and up-to-date reference.

## Performance Tips

- Use appropriate `render_size` values (avoid excessive resolution)
- Enable `use_worker_thread` for better performance on multi-core systems
- Consider frame caching for frequently used animations
- Adjust `engine_option` (0=Default, 1=SmartRender) based on your needs
- On web builds, disable worker threads for better compatibility

## Troubleshooting

### Build Issues

**Meson not found (Windows):**
The build script will automatically install Meson if missing. If you encounter issues:
```bash
pip install --user meson ninja
# Restart terminal to reload PATH
```

**Meson not found (Linux/macOS):**
```bash
pip3 install --user meson ninja
# Or use system package manager:
# Ubuntu/Debian: sudo apt install meson ninja-build
# macOS: brew install meson ninja
```

**Compiler not found:**
- Windows: Install Visual Studio Build Tools
- Linux: `sudo apt install build-essential`
- macOS: `xcode-select --install`

**Submodule errors:**
```bash
git submodule update --init --recursive --force
```

### Runtime Issues

**Poor performance:**
- Verify SIMD is enabled in build output
- Check that multi-threading is working
- Reduce render resolution if needed

**Loading errors:**
- Ensure Lottie files are valid JSON format
- Check file path accessibility
- Verify the plugin is properly enabled

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-feature`
3. Commit changes: `git commit -m 'Add new feature'`
4. Push to branch: `git push origin feature/new-feature`
5. Submit a pull request

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.

## Acknowledgments

- **ThorVG Team** - High-performance vector graphics library
- **Godot Engine** - Open source game engine
- **LottieFiles** - vector animation library powered by ThorVG
