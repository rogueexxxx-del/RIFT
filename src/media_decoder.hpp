// MediaDecoder - async media -> GPU. libav (FFmpeg C API) demux/decode on a
// worker thread, hardware decode (D3D11VA/NVDEC) when available, feeding a
// bounded FrameQueue the render thread pulls from. Replaces the prototype's
// imageio/pyav path (media_loader.py) which decoded on the UI thread.
//
// Images (incl. rasterized SVG) and video share this interface: an image is a
// 1-frame source held static.
#pragma once
#include <string>
#include <thread>
#include <atomic>
#include <memory>
#include "frame_queue.hpp"

namespace rift {

class RhiContext;   // for GPU-interop upload of decoded frames

class MediaDecoder {
public:
    explicit MediaDecoder(RhiContext* rhi);
    ~MediaDecoder();

    struct Ff;                    // libav state (defined in media_decoder.cpp);
                                  // public so file-local helpers can name it

    // Non-blocking open on the worker thread. Poll ready().
    void open(const std::string& path);
    bool ready() const  { return ready_.load(); }
    bool isVideo() const { return is_video_.load(); }
    void size(int& w, int& h) const { w = w_; h = h_; }
    double fps() const { return fps_; }
    double duration() const { return duration_; }

    // Render thread: get the frame for this playhead (from the queue).
    // Uploads to GPU here if the frame arrived as CPU RGBA. Returns a GPU
    // texture handle valid for this frame. 0 if nothing ready yet.
    uint32_t frameForPlayhead(double playhead);

    // Export mode: frameForPlayhead WAITS for the frame that covers the
    // playhead instead of serving whatever is decoded. Playback renders at
    // wall-clock and must never block, but an export runs as fast as the GPU
    // allows and would otherwise outrun the decoder and write blank frames.
    void setBlocking(bool on) { blocking_.store(on); }

    void seek(double seconds);   // flush queue + seek demuxer
    void setLoop(bool on) { loop_.store(on); }
    void stop();

private:
    void worker_(std::string path);   // demux/decode loop

    RhiContext*        rhi_;
    FrameQueue         queue_{8};
    std::thread        thread_;
    std::atomic<bool>  running_{false};
    std::atomic<bool>  ready_{false};
    std::atomic<bool>  is_video_{false};
    std::atomic<bool>  loop_{true};
    std::atomic<bool>  blocking_{false};
    std::atomic<double> seek_req_{-1.0};

    int    w_ = 0, h_ = 0;
    double fps_ = 30.0, duration_ = 0.0;

    // Reusable media texture (last uploaded frame) + which frame it holds, so
    // a re-served frame (static image, underrun) isn't re-uploaded each tick.
    uint32_t static_tex_ = 0;
    int64_t  last_up_ = -1;

    std::unique_ptr<Ff> ff_;      // libav state (Ff declared public above)
};

// Frame-selection contract (must match prototype media_loader.get_frame):
//   target = int(playhead * fps) % total_frames   (video loops)
// The decoder honors pts; this helper documents the index the render thread
// expects so parity with the prototype is exact.
inline int64_t frame_index_for(double playhead, double fps, int64_t total) {
    if (total <= 0) return 0;
    int64_t i = static_cast<int64_t>(playhead * fps);
    return ((i % total) + total) % total;
}

} // namespace rift
