// AudioMixer - the timeline's audio tracks, summed in real time.
//
// This is Approach B from the Phase 1 design: the audio device callback sums
// every placed audio clip live, so per-clip gain is heard immediately. Each
// clip's source is decoded ONCE to f32 stereo at a single rate (kMixRate) and
// kept in RAM; the callback never decodes, so it can never underrun on I/O.
//
// Threading:
//   Render/UI thread : setClips() (decode + build a new immutable Set),
//                      setGain(), the offline renderMono()/renderRange().
//   Audio thread     : mix(), reading the published Set lock-free.
// The clip Set is immutable once published and swapped with an atomic
// shared_ptr, so the callback holds no lock and the previous Set is freed
// when its last reference drops. Gains are per-clip atomics so a fader move
// does not rebuild the Set.
//
// Decode is libav (the dependency the exporter already uses), so any container
// the app accepts works - wav, mp3, m4a, ogg, and the audio stream of a video
// file. A build without FFmpeg gets no audio decode (the mixer stays silent).
#pragma once
#include <atomic>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>
#include "timeline.hpp"     // AudioClipSpec

namespace rift {

// The mixer's fixed output format. Every clip is resampled to this on decode,
// so the callback is pure integer-add mixing.
inline constexpr int kMixRate     = 48000;
inline constexpr int kMixChannels = 2;

class AudioMixer {
public:
    AudioMixer();
    ~AudioMixer();

    // ── render / UI thread ──
    // Decode sources that are not already decoded (reused by path), resolve
    // placements, and publish a new immutable Set to the audio thread.
    void setClips(const std::vector<AudioClipSpec>& clips);
    // Live fader. Indexed like the spec list handed to setClips; a no-op when
    // the index is gone.
    void setGain(int index, float gain);

    bool   empty() const;
    int    count() const;
    int    laneCount() const;                 // A-tracks in use (minimum 1)
    double duration() const;                  // seconds, end of the last clip
    double clipStart(int i) const;            // resolved timeline seconds
    double clipSpan(int i) const;             // placed span, seconds

    // ── audio thread ──
    // Fill `out` (interleaved stereo, kMixRate) from the mix. No locks, no
    // decode. Silence while stopped. Wraps at duration() when looping.
    void mix(float* out, uint32_t frames);
    int64_t cursor() const { return cursor_.load(std::memory_order_acquire); }
    double  cursorSeconds() const { return double(cursor()) / double(kMixRate); }
    void    seek(int64_t frame) { seek_req_.store(frame, std::memory_order_release); }
    void    setLoop(bool on) { loop_.store(on, std::memory_order_release); }
    void    start() { playing_.store(true,  std::memory_order_release); }
    void    stop()  { playing_.store(false, std::memory_order_release); }
    bool    playing() const { return playing_.load(std::memory_order_acquire); }

    // ── offline (render thread) ──
    // Mono mix of the whole timeline, for reactivity/waveform/beats.
    void renderMono(std::vector<float>& out) const;
    // Interleaved stereo for [startFrame, startFrame+frames) - export.
    void renderRange(float* out, int64_t startFrame, int64_t frames) const;

    // Decode a source file to interleaved f32 stereo at kMixRate. false on
    // failure (unknown format, unreadable file, or a no-FFmpeg build).
    static bool decode(const std::string& path, std::vector<float>& out);

private:
    struct Decoded;   // a decoded source, shared across placements by path
    struct Placed;    // a placement of a Decoded on the timeline
    struct Set;       // immutable published snapshot

    // Audio thread: apply a pending seek, at the top of mix().
    void applyCommands_();

    // Published clip set. atomic<shared_ptr> so the callback can read it
    // without a lock and the old set is retired when its last ref drops.
    std::atomic<std::shared_ptr<const Set>> set_{};

    std::atomic<int64_t> cursor_{0};
    std::atomic<int64_t> seek_req_{-1};
    std::atomic<bool>    loop_{true};
    std::atomic<bool>    playing_{false};
};

} // namespace rift
