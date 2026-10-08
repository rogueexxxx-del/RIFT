// AudioSystem - runtime audio: playback + per-frame channel resolution.
//
// Offline path (default): loads the precomputed .analysis blob, and each
// render tick maps playhead -> analysis frame -> raw targets -> Smoother ->
// ChannelRing. The heavy stem separation already happened offline; runtime is
// a lookup + 10-channel exponential smooth (microseconds).
//
// Live path (P3b): miniaudio input callback -> pffft band split -> targets,
// same Smoother, same ring. (Skeleton; pffft wiring marked <<PFFFT>>.)
//
// Playback via miniaudio (header-only). Smoother/AnalysisSource are the
// numerically-validated core (parity check A).
#pragma once
#include <string>
#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <vector>
#include "analysis_source.hpp"
#include "smoother.hpp"
#include "channel_ring.hpp"
#include "audio_mixer.hpp"
#include "timeline.hpp"       // AudioClipSpec

namespace rift {

class AudioSystem {
public:
    // Both ctor and dtor are out-of-line (defined in the .cpp) because the
    // unique_ptr<Ma> PIMPL member needs Ma complete to generate its dtor.
    explicit AudioSystem(ChannelRing* ring);
    ~AudioSystem();

    // Offline: analysis blob drives channels; audio_path is played for monitor.
    bool load(const std::string& audio_path, const std::string& analysis_path);

    // Audio-track mixing (Phase 1). Declarative: decodes sources that are new,
    // mixes clips live during playback, and rebuilds the channel/waveform/beat
    // data from the mix. `analysis_path` is kept only for the single-clip
    // optimization below - a multi-clip mix cannot use a per-file blob.
    bool setAudioClips(const std::vector<AudioClipSpec>& clips,
                       const std::string& analysis_path = {});

    // Single-clip projects that carry a precomputed .analysis blob keep the
    // numerically validated offline channel path, so an existing project reacts
    // exactly as before. Any other case analyzes the mix with the live FFT.
    int    audioClipCount() const { return mixer_ ? mixer_->count() : 0; }
    int    audioLaneCount() const { return mixer_ ? mixer_->laneCount() : 1; }
    double audioClipStart(int i) const { return mixer_ ? mixer_->clipStart(i) : 0.0; }
    double audioClipSpan(int i) const { return mixer_ ? mixer_->clipSpan(i) : 0.0; }
    bool   empty() const { return !mixer_ || mixer_->empty(); }

    // Offline bounce of the mix over [start, start+dur) to a stereo f32 WAV,
    // for the exporter. false when there is nothing to write.
    bool renderMixToWav(const std::string& path, double start, double dur) const;

    bool ready() const { return ready_.load(); }

    void play();
    void pause();
    void seek(double seconds);
    void setLoop(bool on) {
        loop_.store(on);
        if (mixer_) mixer_->setLoop(on);   // the mix wraps with the track
    }
    double playhead() const;
    // True once a real audio device + decoded sound exist. When true the
    // device is the master clock and the engine must defer to playhead(),
    // or the visuals drift away from what is actually being heard.
    bool hasPlayback() const;
    bool isPlaying() const { return playing_.load(); }
    // Peak envelope of the loaded audio, one value per bucket across the whole
    // file, 0..1. Built once at load; empty when no audio is loaded. The
    // timeline draws this as the waveform.
    //
    // A COPY, taken under data_mu_. Handing out a reference let the UI thread
    // walk this vector while a load on the render thread was clearing and
    // refilling it - a read straight through a reallocation.
    std::vector<float> waveform() const;

    // ── visualiser feed ──
    // A window of samples around the playhead, and its spectrum. This is
    // what an oscilloscope / spectrum / spectrogram effect draws; the 10
    // reactive channels are a summary and cannot reconstruct a waveform.
    //
    // Works for file playback (from the decoded PCM) and for live input
    // (from the capture ring), so a scope shows something in both modes.
    // `wave` is centred on the playhead, -1..1. `spec` is magnitude, 0..1,
    // low frequency first. Both are resampled to whatever size you ask for.
    void visualiser(double playhead, float* wave, int nwave,
                    float* spec, int nspec);

    // ── Minimeters visualizer suite shared tap ──
    struct VisualizerTap {
        static constexpr int kCapacity = 8192;
        float L[kCapacity] = {0};
        float R[kCapacity] = {0};
        float mono[kCapacity] = {0};
        uint32_t sampleRate = 48000;
    };
    void updateVisualizerTap(double playhead);
    const VisualizerTap& visualizerTap() const { return tap_; }

    // 1. Oscilloscope: locked, sharp, zero-crossing hysteresis + sub-sample offset
    void getOscilloscope(double playhead, float* outW, int nW, float windowMs = 0.0f);

    // 2. Spectrum Analyzer: 4096-sample Hann FFT, log bins 20Hz-20kHz, dB domain visual fall smoothing, slope compensation.
    // Also caches raw dB array for Spectrogram so FFT is computed once.
    void getSpectrum(double playhead, float* outSpec, int nSpec, float dt = 0.016f, float slopeDbPerOct = 3.0f);
    // 3. Raw dB spectrum (0..1 normalized from -90..0 dB) shared with Spectrogram
    const std::vector<float>& rawSpectrum() const { return raw_spec_; }

    // 4. Lissajous Vectorscope: stereo L/R rotated 45 deg into mid/side (X=side, Y=mid).
    void getVectorscope(double playhead, float* outX, float* outY, int nPairs);

    // Beat/onset times in seconds, computed once at load. Empty when no audio
    // is loaded. Drives the timeline's markers and keyframe snapping.
    std::vector<double> beats() const;

    // Bumped once per completed load. A poller cannot use the waveform's LENGTH
    // to notice a new track - it is always the same bucket count - so loading a
    // second file left the timeline drawing the first one's peaks and beats.
    uint32_t dataGeneration() const { return data_gen_.load(std::memory_order_acquire); }
    // Tempo from the analysis blob, 0 when unknown (incl. any multi-clip mix,
    // which has no blob).
    float bpm() const { return blob_active_ ? src_.bpm() : 0.f; }

    // Track length in seconds.
    //
    // The mix's length (end of the last audio clip) is what a piece runs to
    // now; the blob's length is used only in the single-clip optimization,
    // where it equals the clip's span anyway. Falls back to the decoded
    // length when there is no audio at all.
    double duration() const {
        if (blob_active_ && src_.frames() && src_.sr())
            return double(src_.frames()) * src_.hop() / src_.sr();
        if (mixer_ && !mixer_->empty())
            return mixer_->duration();
        return wave_dur_;
    }

    // Called once per render frame with the current playhead. Advances the
    // Smoother and publishes to the ChannelRing. Frame-rate-locked like the
    // prototype's per-paintGL update().
    void tick(double playhead);

    // Every source the machine can listen to: microphones AND the output of
    // whatever is currently playing. Each entry is
    //   { name, loopback }
    // where loopback means "the mix being sent to this output device", which is
    // how a DAW or any other program becomes the audio source without a virtual
    // cable or a plugin.
    struct LiveDevice { std::string name; bool loopback; };
    std::vector<LiveDevice> liveDevices();
    // Index into liveDevices(); -1 keeps the current choice (default input).
    void setLiveDevice(int index);
    int  liveDevice() const { return live_dev_; }

    // Live input mode (mic/loopback) instead of a file. Channels are derived
    // from a running FFT of the captured signal rather than the .analysis blob.
    void startLive();
    void stopLive();
    bool liveMode() const { return live_.load(); }
    // Input level (peak of the most recent block), for a UI meter / "is the
    // mic actually picking anything up" check.
    float liveLevel() const { return live_level_.load(); }

    // Quality/latency knob for the live FFT (256/512/1024).
    void setLiveFftSize(int n) { live_fft_.store(n); }

private:
    ChannelRing*    ring_;
    AnalysisSource  src_;
    Smoother        smoother_;

    // The timeline's audio tracks, summed live. Always present; empty until
    // clips are set.
    std::unique_ptr<AudioMixer>  mixer_;
    std::vector<AudioClipSpec>   audio_clips_;     // render-thread copy
    std::string                  analysis_path_;   // for the single-clip blob
    bool                         blob_active_ = false;

    std::atomic<bool>   ready_{false};
    std::atomic<bool>   playing_{false};
    std::atomic<bool>   loop_{true};
    std::atomic<bool>   live_{false};
    std::atomic<int>    live_fft_{512};
    int                 live_dev_ = -1;    // index into liveDevices()
    std::atomic<double> playhead_{0.0};
    std::atomic<float>  live_level_{0.f};
    std::vector<float>  wave_;      // peak envelope, built at load
    // Whole decoded track, mono. Needed because a scope wants the actual
    // samples at the playhead, which the peak envelope has thrown away.
    std::vector<float>  pcm_;
    uint32_t            pcm_rate_ = 0;
    // Scratch for visualiser(), so a per-frame call allocates nothing.
    std::vector<float>  vis_in_, vis_out_, vis_work_, vis_win_;
    void*               vis_fft_ = nullptr;   // PFFFT_Setup*
    void*               spec_fft_ = nullptr;  // PFFFT_Setup* 4096
    float*              spec_in_ = nullptr;
    float*              spec_out_ = nullptr;
    float*              spec_work_ = nullptr;
    std::vector<float>  spec_win_;
    std::vector<float>  vis_smooth_db_;
    std::vector<float>  raw_spec_;
    VisualizerTap       tap_;
    int                 last_scope_trigger_i_ = 0;
    std::vector<double> beats_;     // onset times, built at load
    // Guards wave_ and beats_ only: they are rebuilt on the render thread at
    // load time and read from the UI thread every tick. pcm_ needs no guard -
    // it is only ever touched on the render thread.
    mutable std::mutex      data_mu_;
    std::atomic<uint32_t>   data_gen_{0};
    double wave_dur_ = 0.0;         // decoded length, for the no-blob fallback
    // Rebuild pcm_ (now the MONO MIX of the audio tracks) plus wave_/beats_/
    // ready_ from the mixer after a structural change. Replaces the old
    // decode-one-file waveform build: reactivity, the waveform strip and beat
    // detection all read the mix now.
    void rebuildMixData_();
    // Onsets from the analysis blob when there is one, otherwise from the
    // waveform envelope - loading audio without a precomputed blob is normal,
    // and markers are still useful there.
    void buildBeats_(double duration_hint);

public:
    struct Ma;                     // miniaudio + pffft state; public so the
                                   // file-local capture callback can name it
private:
    std::unique_ptr<Ma> ma_;
    // Render thread: newest captured block -> FFT -> 10 channel targets.
    void analyzeLive_(float* targets);
    // Same thing for a loaded FILE with no .analysis blob beside it: copies the
    // window around the playhead into the capture ring and runs the identical
    // analysis. Without this, loading a plain wav leaves all 10 channels at
    // zero - the meters sit still and nothing audio-reactive moves.
    bool analyzeFromPcm_(double playhead, float* targets);
};

} // namespace rift
