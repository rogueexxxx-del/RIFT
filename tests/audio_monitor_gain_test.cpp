// Standalone diagnostic: link with rift_core and its audio libraries.
// Pass a disposable directory for the generated fixture and bounce.
#include "audio_system.hpp"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <thread>
#include <vector>

using namespace rift;

static void require(bool ok, const char* message) {
    if (!ok) throw std::runtime_error(message);
}

static std::vector<float> readWav(const std::filesystem::path& path) {
    std::ifstream f(path, std::ios::binary);
    f.seekg(40);
    uint32_t bytes = 0;
    f.read(reinterpret_cast<char*>(&bytes), 4);
    std::vector<float> pcm(bytes / sizeof(float));
    f.read(reinterpret_cast<char*>(pcm.data()), bytes);
    require(bool(f), "could not read bounce");
    return pcm;
}

int main(int argc, char** argv) try {
    require(argc == 2, "usage: audio_monitor_gain_test <disposable-directory>");
    const std::filesystem::path dir(argv[1]);
    std::filesystem::create_directories(dir);
    const auto source = dir / "monitor-gain-source.wav";
    const auto bounce = dir / "monitor-gain-bounce.wav";
    require(!std::filesystem::exists(source) && !std::filesystem::exists(bounce),
            "fixture paths already exist; use an empty disposable directory");
    // Quiet/loud/quiet/over-range/quiet exposes any gain attack or recovery.
    const float amplitudes[] = {0.125f, 0.5f, 0.125f, 1.5f, 0.125f};
    const int64_t frames = 10 * kMixRate;
    std::vector<float> fixture(size_t(frames) * 2);
    for (int64_t i = 0; i < frames; ++i) {
        const float sample = amplitudes[i / (2 * kMixRate)]
                           * std::sin(2.0 * 3.141592653589793 * 1000.0 * double(i) / kMixRate);
        fixture[size_t(i) * 2] = sample;
        fixture[size_t(i) * 2 + 1] = sample * 0.5f; // also detect accidental mono playback
    }
    {
        std::ofstream f(source, std::ios::binary);
        auto w32 = [&](uint32_t v) { f.write(reinterpret_cast<const char*>(&v), 4); };
        auto w16 = [&](uint16_t v) { f.write(reinterpret_cast<const char*>(&v), 2); };
        const auto bytes = uint32_t(fixture.size() * sizeof(float));
        f.write("RIFF", 4); w32(36 + bytes); f.write("WAVEfmt ", 8);
        w32(16); w16(3); w16(2); w32(kMixRate); w32(kMixRate * 8);
        w16(8); w16(32); f.write("data", 4); w32(bytes);
        f.write(reinterpret_cast<const char*>(fixture.data()), bytes);
        require(bool(f), "could not write fixture");
    }
    AudioClipSpec clip;
    clip.path = source.string();
    clip.start = 0;
    AudioMixer mixer;
    mixer.setClips({clip});
    require(mixer.count() == 1, "FFmpeg fixture decode failed");
    std::vector<float> offline(fixture.size());
    mixer.renderRange(offline.data(), 0, frames);
    require(offline == fixture, "float WAV decode changed samples");

    const uint32_t sizes[] = {1, 127, 480, 1024, 4093};
    size_t blocks = 0, clipped = 0;
    for (int pass = 0; pass < 3; ++pass) {
        mixer.seek(0);
        mixer.setLoop(false);
        mixer.start();
        int64_t pos = 0;
        while (pos < frames) {
            const auto n = uint32_t(std::min<int64_t>(sizes[blocks % 5], frames - pos));
            std::vector<float> monitor(size_t(n) * 2);
            mixer.mix(monitor.data(), n);
            for (size_t j = 0; j < monitor.size(); ++j) {
                const float expected = offline[size_t(pos) * 2 + j];
                require(monitor[j] == std::clamp(expected, -1.f, 1.f),
                        "monitor gain changed relative to decoded/offline PCM");
                if (pass == 0 && expected != monitor[j]) ++clipped;
            }
            pos += n;
            require(mixer.cursor() == pos, "callback cursor drift");
            // Re-publishing unchanged clips must not alter gain or cursor.
            if (++blocks % 23 == 0) mixer.setClips({clip});
        }
    }
    std::printf("PASS: 30 seconds, %zu callback blocks: exact unity gain below full scale; no attack/recovery\n", blocks);
    std::printf("OBSERVED: %zu over-range samples hard-clipped in monitor, unchanged offline\n", clipped);

    mixer.stop();
    const auto stopped = mixer.cursor();
    float buffer[32];
    mixer.mix(buffer, 16);
    require(std::all_of(buffer, buffer + 32, [](float f) { return f == 0; }), "pause not silent");
    require(mixer.cursor() == stopped, "pause advanced cursor");
    mixer.setGain(0, 0.25f);
    mixer.seek(100);
    mixer.start();
    mixer.mix(buffer, 16);
    for (size_t j = 0; j < 32; ++j)
        require(buffer[j] == fixture[200 + j] * 0.25f, "explicit gain/seek incorrect");
    std::printf("PASS: pause, seek, and explicit 0.25 gain\n");

    // Real analysis AGC and visualizers run without opening a playback device.
    ChannelRing ring;
    AudioSystem system(&ring);
    require(system.setAudioClips({clip}, {}, false), "AudioSystem fixture load failed");
    require(!system.hasPlayback(), "offline diagnostic opened playback device");
    require(system.renderMixToWav(bounce.string(), 0, 10), "initial bounce failed");
    const auto before = readWav(bounce);
    float wave[128], spec[128], x[128], y[128];
    for (int i = 0; i < 600; ++i) {
        const double t = double(i) / 60;
        system.tick(t);
        system.visualiser(t, wave, 128, spec, 128);
        system.updateVisualizerTap(t);
        system.getOscilloscope(t, wave, 128);
        system.getSpectrum(t, spec, 128);
        system.getVectorscope(t, x, y, 128);
    }
    require(system.renderMixToWav(bounce.string(), 0, 10), "post-analysis bounce failed");
    require(readWav(bounce) == before && before == fixture,
            "analysis/visualizer AGC modified audible source or offline gain");
    std::printf("PASS: 600 analysis/visualizer ticks leave stereo bounce bit-identical to source\n");
    const auto sourcePeaks = system.audioClipWaveform(0);
    require(sourcePeaks && sourcePeaks->path == source.string()
            && sourcePeaks->duration == 10.0 && !sourcePeaks->peaks.empty(),
            "missing source waveform snapshot");
    auto peakAt = [&](const auto& data, double seconds) {
        return data->peaks.at(size_t(seconds / data->duration * data->peaks.size()));
    };
    require(std::abs(peakAt(sourcePeaks, 1.0) - 0.125f) < 1e-5f
         && std::abs(peakAt(sourcePeaks, 3.0) - 0.5f) < 1e-5f
         && std::abs(peakAt(sourcePeaks, 7.0) - 1.5f) < 1e-5f,
            "source peak envelope does not match source time");
    AudioClipSpec trimmed = clip;
    trimmed.start = 40;
    trimmed.in = 2;
    trimmed.out = 4;
    trimmed.gain = 0.25;
    mixer.setClips({clip, trimmed});
    const auto original = mixer.clipWaveform(0);
    const auto trimPeaks = mixer.clipWaveform(1);
    require(original && original == trimPeaks && trimPeaks->duration == 10.0,
            "placements must share cached full-source envelope independent of trim/gain");
    require(std::abs(peakAt(trimPeaks, trimmed.in + 1.0) - 0.5f) < 1e-5f,
            "trim must map through source-in rather than timeline-start");
    mixer.setClips({trimmed});
    require(mixer.clipWaveform(0) == original, "move/trim re-created source envelope");
    require(!mixer.clipWaveform(-1) && !mixer.clipWaveform(1), "invalid waveform index not empty");
    mixer.setClips({});
    require(!mixer.clipWaveform(0) && original->duration == 10.0,
            "source snapshot did not survive clip replacement");
    std::printf("PASS: source peaks match envelope; trim/gain reuse immutable full-source snapshot\n");
    // A distinct source starts silently; the global mix cannot represent both clips.
    {
        std::fstream f(bounce, std::ios::in | std::ios::out | std::ios::binary);
        std::vector<float> silence(2 * kMixRate * 2, 0.f);
        f.seekp(44);
        f.write(reinterpret_cast<const char*>(silence.data()), silence.size() * sizeof(float));
        require(bool(f), "could not write second envelope fixture");
    }
    AudioClipSpec other = clip;
    other.path = bounce.string();
    mixer.setClips({clip, trimmed, other});
    const auto first = mixer.clipWaveform(0);
    const auto second = mixer.clipWaveform(2);
    require(first == mixer.clipWaveform(1), "first publication decoded duplicate placements separately");
    require(first != second && peakAt(first, 1) > 0 && peakAt(second, 1) == 0
         && std::abs(peakAt(second, 3) - 0.5f) < 1e-5f,
            "different sources incorrectly share envelope");
    std::atomic<bool> reading{true}, valid{true};
    std::thread reader([&] {
        while (reading.load()) {
            const auto data = mixer.clipWaveform(0);
            if (!data || data->duration != 10.0 || data->peaks.empty()) valid.store(false);
        }
    });
    for (int i = 0; i < 500; ++i) {
        if (i % 2) mixer.setClips({clip, other});
        else mixer.setClips({other, clip});
    }
    reading.store(false);
    reader.join();
    require(valid.load(), "source waveform reader saw an incomplete publication");
    std::printf("PASS: distinct source envelopes; shared first decode; concurrent reads across 500 publications\n");
    std::filesystem::remove(source);
    std::filesystem::remove(bounce);
    return 0;
} catch (const std::exception& e) {
    std::fprintf(stderr, "FAIL: %s\n", e.what());
    return 1;
}
