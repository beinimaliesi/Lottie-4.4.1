// Exercises the real ThorVG ownership graph without Godot's process-wide caches.
// Build with -DLOTTIE_LIFECYCLE_TESTS and link the same ThorVG archive as the addon.
#include "lottie_thorvg_owner.h"
#include <cassert>
#include <cstdio>
#include <vector>

int main(int argc, char **argv) {
    assert(argc == 2);
    assert(tvg::Initializer::init(0) == tvg::Result::Success);
    std::vector<uint32_t> pixels(64 * 64);
    auto *canvas = tvg::SwCanvas::gen();
    assert(canvas);
    assert(canvas->target(pixels.data(), 64, 64, 64, tvg::ColorSpace::ARGB8888S) == tvg::Result::Success);
    for (int i = 0; i < 1000; ++i) {
        auto animation = lottie::make_animation();
        auto *picture = animation->picture();
        assert(picture->refCnt() == 1);
        if (i % 4 == 0) {
            assert(picture->load("/nonexistent/lottie-lifecycle-test.json") != tvg::Result::Success);
            continue; // Failed candidates are owned even before reaching Canvas.
        }
        assert(picture->load(argv[1]) == tvg::Result::Success);
        animation->frame(30);
        assert(canvas->add(picture) == tvg::Result::Success);
        assert(picture->refCnt() == 2);
        if (i % 4 != 1) {
            assert(canvas->update() == tvg::Result::Success);
            assert(canvas->draw(false) == tvg::Result::Success);
            // release_animation must synchronize pending rendering itself.
        }
        lottie::release_animation(canvas, animation, picture);
        assert(canvas && !animation && !picture);
    }
    delete canvas;
    assert(tvg::Initializer::term() == tvg::Result::Success);
    assert(lottie::animations_created == 1000);
    assert(lottie::animations_created == lottie::animations_destroyed);
    assert(lottie::unexpected_picture_refs == 0);
    std::puts("ANIMATION_OWNER_TEST PASS: 1000 allocations / 1000 destructions");
}
