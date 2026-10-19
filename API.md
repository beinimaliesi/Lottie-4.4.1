# LottieAnimation API

The plugin ships two nodes:

- **`LottieAnimation`** (extends `Node2D`) — Lottie playback for 2D scenes / UI.
- **`LottieAnimation3D`** (extends `Sprite3D`) — the same Lottie playback projected
  onto a quad in 3D space. See [LottieAnimation3D](#lottieanimation3d) below.

## LottieAnimation

### Properties

- `animation_path : String` — Path to `.json` or `.lottie` file
- `playing : bool` — Animation playback state
- `autoplay : bool` — Start automatically when ready
- `looping : bool` — Loop when reaching end
- `speed : float` — Playback speed (1.0 = normal)
- `fit_box_size : Vector2i` — Display size
- `offset : Vector2` — Drawing offset for pivot adjustment

### Methods

- `play()` — Start/resume playback
- `stop()` — Stop and reset to frame 0
- `pause()` — Pause at current frame
- `seek(frame: float)` — Jump to specific frame
- `get_frame() -> float` — Current frame
- `get_duration() -> float` — Duration in seconds
- `get_total_frames() -> float` — Total frame count

### Signals

- `animation_finished()` — Emitted when non-looping animation ends
- `frame_changed(frame: float)` — Emitted on frame change
- `animation_loaded(success: bool)` — Emitted after load attempt

### Basic Usage

```gdscript
var lottie = $LottieAnimation
lottie.animation_path = "res://animation.json"
lottie.autoplay = true
lottie.looping = true
```

## LottieAnimation3D

`LottieAnimation3D` extends **`Sprite3D`**, so it plays a Lottie animation on a
quad in 3D space. Every `Sprite3D` feature works unchanged — `billboard`,
`alpha_cut`, `pixel_size`, `axis`, `double_sided`, `modulate`, `texture_filter`,
`render_priority` — plus the usual 3D transform, raycasting and culling.
Internally ThorVG rasterises each frame into the node's `texture` slot.

### Properties

- `animation_path : String` — Path to `.json` or `.lottie` file
- `playing : bool` — Animation playback state
- `autoplay : bool` — Start automatically when ready
- `looping : bool` — Loop when reaching end
- `speed : float` — Playback speed (1.0 = normal)
- `render_size : Vector2i` — Resolution of the rasterised texture (default `512×512`)
- *(plus all inherited `Sprite3D` / `SpriteBase3D` properties)*

### Methods

- `play()` — Start/resume playback
- `stop()` — Stop and reset to frame 0
- `pause()` — Pause at current frame
- `seek(frame: float)` — Jump to specific frame
- `set_frame(frame: float)` — Jump to specific frame
- `get_frame() -> float` — Current frame
- `get_duration() -> float` — Duration in seconds
- `get_total_frames() -> float` — Total frame count
- `get_animation_size() -> Vector2i` — Intrinsic (authored) size of the Lottie

### Signals

- `animation_finished()` — Emitted when non-looping animation ends
- `animation_frame_changed(frame: float)` — Emitted on Lottie frame change.
  Inherited `Sprite3D.frame_changed()` remains the sprite-sheet signal.
- `animation_loaded(success: bool)` — Emitted after load attempt

### Basic Usage

```gdscript
var lottie := LottieAnimation3D.new()
lottie.animation_path = "res://animation.json"
lottie.autoplay = true
lottie.looping = true
lottie.render_size = Vector2i(512, 512)   # rasterisation resolution
lottie.pixel_size = 0.01                  # Sprite3D: world units per texture pixel
lottie.billboard = StandardMaterial3D.BILLBOARD_ENABLED   # always face the camera
lottie.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD         # crisp transparency
add_child(lottie)
```

> **Note:** `render_size` controls the CPU rasterisation resolution; the on-screen
> size of the quad is governed by the inherited `Sprite3D.pixel_size` (and the
> node's 3D scale). Keep `render_size` only as large as needed for performance.

## Demo Scene

Check out `demo/addons/godot_lottie/demo/controldemo.tscn` for a working example with UI controls:

- **Play/Stop buttons** connected to `LottieAnimation` methods
- **Runtime control** of animation playback
- **Simple setup** showing basic integration

```gdscript
# UI buttons for animation control
@onready var play: Button = $play
@onready var stop: Button = $stop

# Reference to the Lottie animation node  
@onready var lottie: LottieAnimation = $LottieAnimation

func _on_play_pressed() -> void:
    lottie.play()

func _on_stop_pressed() -> void:
    lottie.stop()
```

---

*State Machine API coming soon*