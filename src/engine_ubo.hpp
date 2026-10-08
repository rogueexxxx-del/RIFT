// EngineUBO - the fixed std140 uniform block every ported shader declares
// (shaders_qrhi preamble, binding 0). Filled per frame from the channel frame
// + palette + time/resolution. Layout MUST match the shader preamble exactly.
#pragma once
#include "rift/rift_types.h"

namespace rift {

struct EngineUBO {
    float timeRes[4];   // x=time, y=_, z=resX, w=resY
    float A[4];         // bass, melody, highs, drums
    float B[4];         // transient, bpm, centroid, playhead
    float C[4];         // kick, snare, scope_trigger, spectro_row
    float bg[4];        // color_bg.rgb, palette_active
    float fg1[4];       // color_fg1.rgb, _
    float fg2[4];       // color_fg2.rgb, _
};

// Fill from a resolved channel frame (+ time/res, palette optional).
inline EngineUBO makeEngineUBO(const rift_channel_frame& cf, float time,
                               int w, int h) {
    EngineUBO e{};
    e.timeRes[0] = time; e.timeRes[2] = float(w); e.timeRes[3] = float(h);
    e.A[0] = cf.ch[RIFT_CH_BASS];   e.A[1] = cf.ch[RIFT_CH_MELODY];
    e.A[2] = cf.ch[RIFT_CH_HIGHS];  e.A[3] = cf.ch[RIFT_CH_DRUMS];
    e.B[0] = cf.ch[RIFT_CH_TRANSIENT]; e.B[1] = cf.ch[RIFT_CH_BPM];
    e.B[2] = cf.ch[RIFT_CH_CENTROID];  e.B[3] = cf.ch[RIFT_CH_TIME];
    e.C[0] = cf.ch[RIFT_CH_KICK];   e.C[1] = cf.ch[RIFT_CH_SNARE];
    // palette off by default (bg.a = 0); UI sets it later
    return e;
}

} // namespace rift
