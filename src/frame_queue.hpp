// Bounded frame queue: decode thread(s) push decoded frames, render thread
// pops the one matching the current playhead. Bounded so a fast decoder
// can't balloon memory; render never blocks (returns last-good on underrun).
// Handoff is decode->render only (SPSC per stream).
#pragma once
#include <mutex>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <cstdint>
#include <vector>

namespace rift {

// A decoded frame in a GPU-uploadable layout. For HW decode the payload is a
// shared GPU texture handle; for SW decode it's CPU RGBA to be uploaded.
struct DecodedFrame {
    int64_t   frame_index;      // source frame number
    double    pts;              // presentation timestamp (seconds)
    int       w = 0, h = 0;
    bool      is_gpu = false;   // true: gpu_tex valid; false: rgba valid
    uint32_t  gpu_tex = 0;      // HW path (D3D11 shared texture id)
    std::vector<uint8_t> rgba;  // SW path
};

class FrameQueue {
public:
    explicit FrameQueue(size_t cap = 8) : cap_(cap) {}

    // Decoder side. Blocks if full (backpressure) until space or stop().
    bool push(DecodedFrame&& f) {
        std::unique_lock lk(m_);
        cv_full_.wait(lk, [&]{ return q_.size() < cap_ || stop_; });
        if (stop_) return false;
        q_.push_back(std::move(f));
        cv_empty_.notify_one();
        return true;
    }

    // Render side. Returns the frame whose pts is closest-at-or-before
    // `playhead`, discarding older frames. Non-blocking: false if none ready.
    bool pop_for(double playhead, DecodedFrame& out) {
        std::lock_guard lk(m_);
        if (q_.empty()) return false;
        // drop frames strictly older than the playhead (keep newest of them)
        while (q_.size() > 1 && q_[1].pts <= playhead) {
            q_.pop_front();
            cv_full_.notify_one();
        }
        out = q_.front();           // copy current (may re-serve until advance)
        return true;
    }

    // Export side. Same selection as pop_for, but WAITS for a frame that
    // actually covers `playhead` instead of returning whatever happens to be
    // decoded. Playback must never block (a stall would drop frames); an export
    // must never race ahead of the decoder, or it writes stale/blank frames.
    // Returns false on stop() or timeout, so a stuck decoder cannot hang.
    bool pop_for_blocking(double playhead, DecodedFrame& out, int timeout_ms) {
        std::unique_lock lk(m_);
        // "Covers the playhead" = some frame at-or-before it, with either a
        // newer frame behind it or the source exhausted. Waiting for q_.size()>1
        // guarantees the front is the right one rather than merely the first.
        const auto deadline =
            std::chrono::steady_clock::now() + std::chrono::milliseconds(timeout_ms);
        const bool got = cv_empty_.wait_until(lk, deadline, [&] {
            return stop_ || (!q_.empty() &&
                             (q_.back().pts >= playhead || q_.size() >= cap_));
        });
        if (!got || stop_ || q_.empty()) {
            if (q_.empty()) return false;      // nothing at all: caller keeps last
        }
        while (q_.size() > 1 && q_[1].pts <= playhead) {
            q_.pop_front();
            cv_full_.notify_one();
        }
        out = q_.front();
        return true;
    }

    // Called on seek/loop: drop everything so decode can refill from the target.
    void flush() {
        std::lock_guard lk(m_);
        q_.clear();
        cv_full_.notify_all();
    }

    void stop() {
        std::lock_guard lk(m_);
        stop_ = true;
        cv_full_.notify_all();
        cv_empty_.notify_all();
    }

    // Re-arm after a stop() (e.g. reopening media). Clears the stop latch and
    // drops any stale frames so the next decode starts clean.
    void start() {
        std::lock_guard lk(m_);
        stop_ = false;
        q_.clear();
    }

    size_t size() { std::lock_guard lk(m_); return q_.size(); }

private:
    std::deque<DecodedFrame> q_;
    size_t cap_;
    bool   stop_ = false;
    std::mutex m_;
    std::condition_variable cv_full_, cv_empty_;
};

} // namespace rift
