#ifndef LOTTIE_ANIMATION_3D_H
#define LOTTIE_ANIMATION_3D_H

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/sprite3d.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstdint>
#include "lottie_thorvg_owner.h"

namespace tvg {
class SwCanvas;
class Animation;
class Picture;
}

namespace godot {

// LottieAnimation3D plays a Lottie animation in 3D space.
//
// It extends Sprite3D, so every Sprite3D feature works unchanged: billboard
// modes, alpha-cut, pixel_size, axis, double-sided, modulate, transparency,
// render priority, plus normal 3D transform/raycasting/culling. ThorVG
// rasterises each frame on the CPU into an ImageTexture which is fed to the
// Sprite3D texture slot; because Sprite3D subscribes to the texture's
// "changed" signal, ImageTexture::update() each frame triggers a redraw with
// no extra plumbing.
//
// Rendering is synchronous on the main thread (the proven code path the 2D
// node also uses when its worker thread is disabled). Both .json and .lottie
// (dotLottie zip) sources are supported.
class LottieAnimation3D : public Sprite3D {
    GDCLASS(LottieAnimation3D, Sprite3D)

private:
    String animation_path;
    String selected_dotlottie_animation;
    bool playing;
    bool looping;
    bool autoplay;
    float speed;
    float current_frame;
    float total_frames;
    float duration;

    Vector2i render_size;
    Vector2i base_picture_size;

    Ref<Image> image;
    Ref<ImageTexture> lottie_texture;
    PackedByteArray pixel_bytes;

    // Animation owns Picture; Canvas holds an additional Picture reference.
    tvg::SwCanvas *canvas;
    lottie::AnimationOwner animation;
    tvg::Picture *picture; // Owned by `animation`; do not delete directly.
    uint32_t *buffer;

    bool fix_alpha_border;
    bool unpremultiply_alpha;

    int last_rendered_frame_index;
    bool first_frame_drawn;

    void _initialize_thorvg();
    void _cleanup_thorvg();
    bool _load_animation(const String &path);
    void _unload_animation();
    void _allocate_buffer_and_target(const Vector2i &size);
    void _apply_picture_transform_to_fit();
    void _create_texture();
    void _bind_lottie_texture();
    void _update_animation(double delta);
    void _render_frame();

protected:
    static void _bind_methods();

public:
    LottieAnimation3D();
    ~LottieAnimation3D();

    void _ready() override;
    void _process(double delta) override;

    void play();
    void stop();
    void pause();
    void seek(float frame);
    void set_frame(float frame);
    float get_frame() const;

    void set_animation_path(const String &path);
    String get_animation_path() const;

    void set_selected_dotlottie_animation(const String &id);
    String get_selected_dotlottie_animation() const;

    void set_playing(bool p_playing);
    bool is_playing() const;

    void set_looping(bool p_looping);
    bool is_looping() const;

    void set_autoplay(bool p_autoplay);
    bool is_autoplay() const;

    void set_speed(float p_speed);
    float get_speed() const;

    void set_render_size(const Vector2i &size);
    Vector2i get_render_size() const;

    float get_duration() const;
    float get_total_frames() const;
    Vector2i get_animation_size() const;
};

}

#endif // LOTTIE_ANIMATION_3D_H
