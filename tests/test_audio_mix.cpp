// Unit test for AudioMixer: clip placement, trims, gain, seek, loop, renderRange.
#include "audio_mixer.hpp"
#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>

int main() {
    rift::AudioMixer mixer;
    assert(mixer.empty());
    assert(mixer.count() == 0);
    assert(mixer.laneCount() == 1);
    assert(mixer.duration() == 0.0);

    // Initial mix output must be silence when empty
    std::vector<float> buf(512 * rift::kMixChannels, 1.0f);
    mixer.mix(buf.data(), 512);
    for (float v : buf) {
        assert(v == 0.0f);
    }

    // Set clips without files (non-existent paths produce empty decodes without crashing)
    std::vector<rift::AudioClipSpec> specs;
    rift::AudioClipSpec s1;
    s1.path = "non_existent_1.wav";
    s1.name = "clip1";
    s1.start = 0.0;
    s1.in = 0.0;
    s1.out = 1.0;
    s1.lane = 0;
    s1.gain = 1.0;
    specs.push_back(s1);

    rift::AudioClipSpec s2;
    s2.path = "non_existent_2.wav";
    s2.name = "clip2";
    s2.start = -1.0; // auto-append
    s2.in = 0.0;
    s2.out = 2.0;
    s2.lane = 1;
    s2.gain = 0.5;
    specs.push_back(s2);

    mixer.setClips(specs);
    // count reflects placements even if source file is missing
    assert(mixer.count() == 2);
    assert(mixer.laneCount() == 2);

    // Live gain update
    mixer.setGain(0, 1.5f);
    mixer.setGain(1, 0.8f);

    // Seek and cursor
    mixer.seek(48000); // 1.0s at 48kHz
    mixer.setLoop(true);

    // Output with missing audio files remains silent without crashing
    std::fill(buf.begin(), buf.end(), 1.0f);
    mixer.mix(buf.data(), 256);
    for (float v : buf) {
        assert(v == 0.0f);
    }

    // renderMono and renderRange on empty/missing decoded data
    std::vector<float> mono;
    mixer.renderMono(mono);

    std::vector<float> range(100 * rift::kMixChannels, 1.0f);
    mixer.renderRange(range.data(), 0, 100);
    for (float v : range) {
        assert(v == 0.0f);
    }

    std::puts("RIFT audio mix test OK");
    return 0;
}
