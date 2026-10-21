#ifndef LOTTIE_THORVG_OWNER_H
#define LOTTIE_THORVG_OWNER_H

#include <thorvg.h>
#include <memory>
#include <mutex>
#ifdef LOTTIE_LIFECYCLE_TESTS
#include <atomic>
#endif

namespace lottie {

// ThorVG's LottieExpressions/JerryScript engine is process-global and explicitly
// does not support concurrent callers. Its internal scheduler can be disabled
// while our own node workers still run. Serialize ThorVG operations across all
// 2D/3D instances, including load, evaluation and destruction. Do not hold this
// lock while joining workers or emitting Godot callbacks.
inline std::recursive_mutex &engine_mutex() {
    static std::recursive_mutex mutex;
    return mutex;
}
using EngineGuard = std::lock_guard<std::recursive_mutex>;

#ifdef LOTTIE_LIFECYCLE_TESTS
// Only exposed in instrumented regression builds, never in distributed binaries.
inline std::atomic<uint64_t> animations_created{0};
inline std::atomic<uint64_t> animations_destroyed{0};
inline std::atomic<uint64_t> unexpected_picture_refs{0};
inline std::atomic<uint64_t> active_workers{0};
#endif

struct AnimationDeleter {
    void operator()(tvg::Animation *animation) const {
        EngineGuard guard(engine_mutex());
#ifdef LOTTIE_LIFECYCLE_TESTS
        // All Canvas references must be detached before releasing the owner.
        if (animation->picture() && animation->picture()->refCnt() != 1) {
            ++unexpected_picture_refs;
        }
#endif
        delete animation;
#ifdef LOTTIE_LIFECYCLE_TESTS
        ++animations_destroyed;
#endif
    }
};
using AnimationOwner = std::unique_ptr<tvg::Animation, AnimationDeleter>;

inline AnimationOwner make_animation() {
    EngineGuard guard(engine_mutex());
    AnimationOwner animation(tvg::Animation::gen());
#ifdef LOTTIE_LIFECYCLE_TESTS
    if (animation) ++animations_created;
#endif
    return animation;
}

// Each canvas belongs exclusively to one node/worker. Call on its rendering
// thread, or after joining that thread. Picture is borrowed, not independently
// owned: remove the Canvas reference, then release Animation's reference.
inline bool release_animation(tvg::SwCanvas *&canvas, AnimationOwner &animation, tvg::Picture *&picture) {
    EngineGuard guard(engine_mutex());
    bool usable_canvas = true;
    if (canvas) {
        canvas->sync();
        if (canvas->remove() != tvg::Result::Success) {
            // Canvas destruction synchronizes outstanding work and drops its
            // scene references. Do not keep using a canvas that failed removal.
            delete canvas;
            canvas = nullptr;
            usable_canvas = false;
        }
    }
    picture = nullptr;
    animation.reset();
    return usable_canvas;
}

} // namespace lottie
#endif
