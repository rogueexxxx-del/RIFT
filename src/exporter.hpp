// Exporter - encode rendered RGBA frames to a video file via libav.
//
// Everything in-process: no Python, no child process (README P6). Picks the
// best available encoder by actually opening it, composites overlays with
// QPainter, and muxes the source audio as AAC.
//
// Encoder ladder (all LGPL - the linked FFmpeg is --disable-libx264):
//   archive -> prores_ks (yuv422p10le)
//   else    -> first of h264_nvenc, h264_qsv, h264_amf, h264_mf, libopenh264
//              that avcodec_open2() actually accepts on this machine.
//
// Driven from the render thread so it shares the single-threaded QRhi context
// for offscreen render + readback.
#pragma once
#include <memory>
#include <string>
#include <cstdint>
#include "rift/rift_types.h"

namespace rift {

class Exporter {
public:
    Exporter();
    ~Exporter();

    // Set up muxer + encoder for `spec` (width/height must be even). false on
    // failure (see error()).
    bool open(const rift_export_spec& spec);
    // Encode one RGBA8 frame (w*h*4), top-down, with optional UTF-8 overlay
    // text centred on it. Must match the spec dimensions.
    bool writeFrame(const uint8_t* rgba, const char* overlay_text = nullptr);
    // Flush encoder + write trailer. Safe to call once after all frames.
    bool finish();

    const char* error() const { return err_.c_str(); }
    // Encoder actually selected ("h264_qsv", "prores_ks", ...). Empty until
    // open() succeeds. Worth logging: which one you get is machine-dependent.
    const std::string& encoder() const { return encoder_; }

    struct Impl;                 // public so file-local libav helpers can name it

private:
    std::unique_ptr<Impl> d_;
    std::string err_;
    std::string encoder_;
};

} // namespace rift
