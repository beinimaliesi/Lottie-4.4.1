# Adding Node3D Support — Step-by-Step Guide

This document describes how the `LottieAnimation3D` node was added to this
GDExtension, end-to-end: investigation, implementation, build-chain setup,
verification, and push. It is meant both as a record of the work that was done
and as a template for similar 2D→3D additions in other GDExtensions.

The change adds a `LottieAnimation3D : Sprite3D` node alongside the existing
`LottieAnimation : Node2D`, without modifying the 2D node's source.

---

## Phase 1 — Understand the existing repo

Before writing any code, get a clear picture of what's already there.

```bash
git clone https://github.com/byourself22/Lottie-godot.git
cd Lottie-godot
git submodule update --init --recursive
```

Files of interest (in order of importance):

| File | What's in it |
|---|---|
| `src/lottie_animation.h` / `.cpp` | The 2D node — Node2D-based, ~1830 lines. Contains the ThorVG render pipeline, an optional worker thread, frame caching, dotLottie (.lottie zip) loading, state-machine manifest parsing, and dynamic resolution. |
| `src/lottie_frame_cache.h` / `.cpp` | LRU singleton shared by 2D instances. Not needed for 3D v1. |
| `src/lottie_state_machine.h` / `.cpp` | Resource classes for state machines. Not needed for 3D v1. |
| `src/register_types.cpp` | GDExtension init — `GDREGISTER_CLASS(...)` for every node. |
| `SConstruct` | Globs `src/*.cpp`. New `.cpp` files are picked up automatically. |
| `demo/addons/godot_lottie/godot_lottie.gdextension` | Lists per-platform library paths and class icons. |

Key reading: the synchronous `_render_frame()` (around line 942 of
`lottie_animation.cpp`) is the **proven** render path. The 3D node should
reuse exactly this pipeline so behaviour and pixel output are identical.

---

## Phase 2 — Design decisions

The architecture for the 3D node followed three rules.

### 2.1 Pick a base class that gives you 3D features for free

Inherit from **`Sprite3D`**, not `Node3D` or `MeshInstance3D`. Sprite3D already
handles:

- Billboard modes (disabled / always / Y-axis)
- Alpha-cut (discard / opaque pre-pass / hash) for crisp transparency
- `pixel_size` (world units per texture pixel)
- Axis, double-sided, modulate, render priority
- AABB, triangle mesh for raycasts and culling

Because `Sprite3D::set_texture()` subscribes to the texture's `changed` signal,
calling `ImageTexture::update()` each frame **auto-triggers a sprite redraw**
with no extra plumbing.

### 2.2 Do not touch the working 2D file

The 2D node has a worker-thread architecture with mutexes; one bad edit and
the shipping 2D node breaks. So:

- Pure utility functions used in the render path (SIMD ARGB→RGBA conversion,
  alpha-border fix, unpremultiply, `.lottie` zip extraction) are duplicated
  into a new **header-only** `src/lottie_common.h`.
- Only the new 3D file includes that header. The 2D file is untouched.
- A future refactor can collapse the duplication, but that's a separate PR.

### 2.3 Start simple, match 2D behaviour exactly

For v1 the 3D node uses the **synchronous** render path (the 2D node's
`_render_frame` body, with `_update` then `draw(false)` then `sync`). No
worker thread, no frame cache, no dynamic resolution from screen scale, no
state-machine UI. Same `.json` + `.lottie` support, same play/pause/stop/seek
API, `animation_finished` / `animation_frame_changed` / `animation_loaded`
signals. The 3D frame signal is named `animation_frame_changed(frame)` to avoid
conflicting with the inherited `Sprite3D.frame_changed()` signal.

---

## Phase 3 — Implementation

### 3.1 `src/lottie_common.h` (new)

Header-only utilities, all functions `inline`, namespaced `lottie::`. ODR-safe
across translation units.

Contents:

- `lottie::convert_argb_to_rgba(src, dst, count)` — SSSE3 / NEON / scalar
- `lottie::fix_alpha_border_rgba(rgba, w, h)`
- `lottie::unpremultiply_alpha_rgba(rgba, w, h)`
- `lottie::mirror_file_to_user_cache(src_path)` — for `res://` paths in PCK
- `lottie::extract_lottie_json_to_cache(zip_path, preferred_entry)` — dotLottie

Function bodies were copied verbatim from the existing static helpers in
`lottie_animation.cpp` (the SIMD shuffle masks are tested and shipping; don't
reinvent them). `using namespace godot;` is fine here because it matches the
repo's convention in `register_types.h`.

### 3.2 `src/lottie_animation_3d.h` (new)

```cpp
class LottieAnimation3D : public Sprite3D {
    GDCLASS(LottieAnimation3D, Sprite3D)
    // ... same playback state as the 2D node: animation_path, playing,
    // looping, autoplay, speed, current_frame, total_frames, duration,
    // plus render_size + base_picture_size, plus the ThorVG pointers.
};
```

Forward-declare ThorVG types in `namespace tvg { class SwCanvas; ... }` so the
header doesn't pull in `<thorvg.h>` into every TU that includes us.

### 3.3 `src/lottie_animation_3d.cpp` (new)

The implementation flow mirrors the 2D node's synchronous path:

```
constructor      -> _initialize_thorvg()
                    -> Initializer::init(threads) (refcounted, safe-twice)
                    -> SwCanvas::gen(SmartRender)
                    -> _allocate_buffer_and_target(512x512)
                        -> _create_texture() (creates Ref<Image> + Ref<ImageTexture>)

_ready()         -> set_process(true)
                 -> _bind_lottie_texture()    // safe in-tree
                 -> if path set: _load_animation() -> renders frame 0

_process(delta)  -> if playing: _update_animation(); _render_frame()

_render_frame()  -> animation->frame(current); canvas->update/draw(false)/sync
                 -> convert_argb_to_rgba(buffer -> pixel_bytes)
                 -> image->set_data(...); lottie_texture->update(image)
                 -> Sprite3D auto-redraws via the texture's "changed" signal
```

### 3.4 Three safety refinements caught during review

1. **Don't touch Sprite3D internals from the constructor.** `_create_texture()`
   was originally calling `set_texture(lottie_texture)`, but
   `_initialize_thorvg()` is invoked from the constructor. Solution: split out
   a `_bind_lottie_texture()` helper called only from `_ready()` and
   `set_render_size()` — both known-safe sites where the object is fully
   constructed.

2. **No cross-type `Ref` comparison.** An earlier version did
   `get_texture() != lottie_texture` (comparing `Ref<Texture2D>` with
   `Ref<ImageTexture>`). godot-cpp's `Ref::operator==` is same-type only.
   Removed the guard entirely — `Sprite3D::set_texture()` already early-outs
   on unchanged input.

3. **`play()` must work before `_ready()`.** Saved scenes with `playing=true`
   call `set_playing(true)` → `play()` during deserialization, before
   `_ready()`. The first attempt guarded `_load_animation()` with
   `is_inside_tree()`, breaking that case. Removed the guard — `_load_animation`
   only uses ThorVG (CPU work) and file I/O, neither requires a tree.

### 3.5 `src/register_types.cpp` (edited)

Two lines added:

```cpp
#include "lottie_animation_3d.h"
...
GDREGISTER_CLASS(LottieAnimation3D);
```

### 3.6 Icon + `.gdextension`

- `demo/addons/godot_lottie/icons/LottieAnimation3D.svg` (new) — same
  LottieFiles brand mark with a stripe motif so it's visually distinct from
  the 2D icon in the scene tree.
- `LottieAnimation3D.svg.import` (new) — copy of the 2D import, with a fresh
  uid and the path strings updated.
- `godot_lottie.gdextension` — one line added under `[icons]`:
  ```
  LottieAnimation3D = "res://addons/godot_lottie/icons/LottieAnimation3D.svg"
  ```

### 3.7 Docs

`API.md` — added a `LottieAnimation3D` section with properties, methods,
signals, and a GDScript usage example.
`README.md` — Features bullet for 3D support, project-structure tree updated,
Usage section mentions the 3D node.

### 3.8 No `SConstruct` change

`sources = Glob("src/*.cpp")` already picks up `lottie_animation_3d.cpp`.
Don't edit what doesn't need editing.

---

## Phase 4 — Verify against godot-cpp before building

Before kicking off a long build, sanity-check every API call against the
fetched godot-cpp `extension_api.json`. Sample queries:

```bash
python -c "
import json
api = json.load(open('thirdparty/godot-cpp/gdextension/extension_api.json'))
def find_class(n): return next(c for c in api['classes'] if c['name']==n)
sp = find_class('Sprite3D')
print([m['name'] for m in sp['methods'] if 'texture' in m['name']])
# -> ['set_texture', 'get_texture', ...]
"
```

Same for `Image::create(int, int, bool, Image.Format)`, `Image::set_data`,
`ImageTexture::create_from_image`, `ImageTexture::update`, and the
`Node::_process(float delta)` / `Node::_ready()` virtual signatures.

Also verify the header-name convention by reading
`thirdparty/godot-cpp/binding_generator.py::camel_to_snake` — it ends with
`.replace("3_D", "3D").lower()`, so `Sprite3D` → `sprite3d.hpp`. That's why
the include is:

```cpp
#include <godot_cpp/classes/sprite3d.hpp>
```

---

## Phase 5 — Build toolchain (Windows)

Prerequisites:

- Visual Studio 2022 BuildTools with the C++ workload (or VS Community/Pro)
- Python 3.10+ with pip
- Git

Install meson + ninja into the user site:

```bash
python -m pip install --user meson ninja
```

The scripts land in `%APPDATA%\Python\Python312\Scripts` (adjust for your
Python version). Add it to PATH for this session, or invoke meson with a
full path.

Make sure `vcvars64.bat` exists:

```
"C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
```

---

## Phase 6 — Build ThorVG

ThorVG is built once into `thirdparty/thorvg/builddir/`. The SConstruct
expects either `thorvg-1.dll` (Windows) or `libthorvg.a` (Linux/macOS) in
that folder.

A small helper batch file does the dance:

```batch
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
set "PATH=%APPDATA%\Python\Python312\Scripts;%PATH%"
cd /d "%~dp0thirdparty\thorvg"
if exist builddir rmdir /s /q builddir
meson setup builddir ^
  -Dbuildtype=release -Doptimization=3 -Db_ndebug=true ^
  -Dsimd=true -Dthreads=true -Dpartial=true ^
  -Dengines=sw -Dloaders=lottie -Dbindings=capi -Dexamples=false ^
  --backend=ninja
meson compile -C builddir
```

Run it from `cmd.exe` (so vcvars64 sticks). The build takes ~2-5 minutes and
produces `thirdparty/thorvg/builddir/src/thorvg-1.dll` plus `thorvg.lib` and
`thorvg.exp`.

---

## Phase 7 — Build the GDExtension

Another helper batch file:

```batch
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
cd /d "%~dp0"
python -m SCons platform=windows target=template_debug -j%NUMBER_OF_PROCESSORS%
```

First build is slow (~10 minutes) because SCons compiles ~990 auto-generated
godot-cpp class wrappers before getting to our 5 source files. Subsequent
incremental builds take seconds.

Output: `demo/addons/godot_lottie/bin/libgodot_lottie.windows.template_debug.x86_64.dll`
(631 KB for this change). The SConstruct also auto-copies `thorvg-1.dll`
next to it.

The build log should show:

```
Compiling shared src\lottie_frame_cache.cpp ...
Compiling shared src\lottie_animation_3d.cpp ...
Compiling shared src\lottie_animation.cpp ...
Compiling shared src\lottie_state_machine.cpp ...
Compiling shared src\register_types.cpp ...
Linking Shared Library demo\addons\godot_lottie\bin\libgodot_lottie.windows.template_debug.x86_64.dll ...
```

If `lottie_animation_3d.cpp` isn't in the compile list, your `src/*.cpp`
glob didn't pick it up — check that the file is actually under `src/`.

---

## Phase 8 — Verify the build output

Confirm the class is in the DLL:

```bash
grep -aoc "LottieAnimation3D" \
  demo/addons/godot_lottie/bin/libgodot_lottie.windows.template_debug.x86_64.dll
# Expect a small positive number (the class name appears in the bind
# registration string and signal/method names).
```

(`strings` with its default 4-char minimum can miss these strings inside the
PE; use `grep -ao` to scan raw bytes.)

---

## Phase 9 — Test in the Godot editor

A minimal verification scene was added at
`demo/addons/godot_lottie/demo/demo3d.tscn`:

- `Camera3D` at `(0, 0, 3)`, `current = true`
- `DirectionalLight3D` (decorative)
- `LottieBillboard` (`LottieAnimation3D`) at `x = -1.2`, `billboard = 1`,
  plays `Godot funny.json`
- `LottieFixed` (`LottieAnimation3D`) at `x = +1.2`, fixed orientation,
  plays `Loader animation.json`

To test:

1. Open `demo/project.godot` in Godot 4.7+ (restart the editor if it was
   already open during the build so it reloads the DLL).
2. Open `res://addons/godot_lottie/demo/demo3d.tscn`.
3. Press **F5** (or **F6** to play just this scene).

Expected:
- Left node: animation plays and stays facing the camera as you orbit.
- Right node: animation plays on a fixed-orientation quad — you can see it
  foreshorten edge-on, which proves it's real 3D geometry.

Quick scripted check (paste into `Project → Tools → Script Editor → Run`):

```gdscript
@tool
extends EditorScript
func _run():
    var c := LottieAnimation3D.new()
    print(c.get_class(), " | is Sprite3D: ", c is Sprite3D,
          " | has play(): ", c.has_method("play"))
```

---

## Phase 10 — Commit & push

Stage only the feature files (don't use `git add -A` — the build leaves
machine-specific batch helpers and a `builddir/` behind that shouldn't be
committed):

```bash
git add \
  src/lottie_animation_3d.h \
  src/lottie_animation_3d.cpp \
  src/lottie_common.h \
  src/register_types.cpp \
  demo/addons/godot_lottie/godot_lottie.gdextension \
  demo/addons/godot_lottie/icons/LottieAnimation3D.svg \
  demo/addons/godot_lottie/icons/LottieAnimation3D.svg.import \
  demo/addons/godot_lottie/demo/demo3d.tscn \
  demo/addons/godot_lottie/bin/libgodot_lottie.windows.template_debug.x86_64.dll \
  demo/addons/godot_lottie/bin/libgodot_lottie.windows.template_debug.x86_64.exp \
  demo/addons/godot_lottie/bin/libgodot_lottie.windows.template_debug.x86_64.lib \
  demo/addons/godot_lottie/bin/thorvg-1.dll \
  API.md \
  README.md
```

(Binaries are committed because this repo's convention is to ship pre-built
addon DLLs alongside source.)

Commit:

```bash
git commit -m "Add LottieAnimation3D node for 3D scenes"
```

Add the destination remote and push:

```bash
git remote add neerajpan https://github.com/neerajpan/Lottie.git
git push -u neerajpan main
```

The first push triggers Git Credential Manager — sign in via the browser
window it pops, then the push proceeds. Subsequent pushes reuse the cached
credential.

---

## Files added / changed in this commit

| Status | File |
|---|---|
| new | `src/lottie_animation_3d.h` |
| new | `src/lottie_animation_3d.cpp` |
| new | `src/lottie_common.h` |
| new | `demo/addons/godot_lottie/icons/LottieAnimation3D.svg` |
| new | `demo/addons/godot_lottie/icons/LottieAnimation3D.svg.import` |
| new | `demo/addons/godot_lottie/demo/demo3d.tscn` |
| modified | `src/register_types.cpp` |
| modified | `demo/addons/godot_lottie/godot_lottie.gdextension` |
| modified | `API.md` |
| modified | `README.md` |
| modified | `demo/addons/godot_lottie/bin/libgodot_lottie.windows.template_debug.x86_64.dll` (rebuilt) |
| modified | `demo/addons/godot_lottie/bin/libgodot_lottie.windows.template_debug.x86_64.exp` |
| modified | `demo/addons/godot_lottie/bin/libgodot_lottie.windows.template_debug.x86_64.lib` |
| modified | `demo/addons/godot_lottie/bin/thorvg-1.dll` (rebuilt) |

Untouched: `src/lottie_animation.h/.cpp`, `src/lottie_frame_cache.*`,
`src/lottie_state_machine.*`, `SConstruct`.

---

## Follow-up work (not in this commit)

- Build and commit `template_release` so runtime exports also use the new node.
- Build Linux / macOS / Android / Web variants (each needs its own ThorVG
  build for that platform).
- Extend `lottie_inspector_plugin.gd` to also target `LottieAnimation3D` so
  the `.lottie` animation-selection dropdown works for the 3D node too.
- Optionally refactor `lottie_animation.cpp` to also use `lottie_common.h`
  and eliminate the duplicated SIMD / zip helpers (separate PR — would touch
  the working 2D node).
