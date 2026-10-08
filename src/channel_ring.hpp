// Lock-free SPSC ring: audio thread pushes channel frames, render thread
// reads the latest. No mutex on the hot path -> no priority inversion,
// no audio-glitch-induced render stall. Mirrors the prototype's per-frame
// AudioEngine.params handoff, but thread-safe by construction.
#pragma once
#include <atomic>
#include <array>
#include "rift/rift_types.h"

namespace rift {

class ChannelRing {
public:
    // Single producer (audio), single consumer (render).
    // Writer publishes to the slot the reader is NOT reading (double buffer
    // + seqlock counter) so the reader always sees a complete frame.
    void push(const rift_channel_frame& f) noexcept {
        unsigned w = (write_.load(std::memory_order_relaxed) + 1u) & 1u;
        slot_[w] = f;
        write_.store(w, std::memory_order_release);
    }

    // Returns the most recent fully-written frame. Never blocks.
    bool latest(rift_channel_frame& out) const noexcept {
        unsigned w = write_.load(std::memory_order_acquire);
        out = slot_[w];
        return true;
    }

private:
    std::array<rift_channel_frame, 2> slot_{};
    std::atomic<unsigned> write_{0};
};

} // namespace rift
