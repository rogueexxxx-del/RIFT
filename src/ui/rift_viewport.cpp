// RiftViewport impl - Engine (external mode) -> QSG texture node.
//
// Per Qt Quick frame:
//   [render thread] beforeRendering() -> Engine::renderExternal() -> TexId
//   [both blocked ] updatePaintNode() -> wrap that QRhiTexture in a QSGTexture
//   [render thread] Quick composites the node like any other item
#include "rift_viewport.hpp"
#include <QQuickWindow>
#include <algorithm>
#include <QSGSimpleTextureNode>
#include <QSGTexture>
// Private, but the only way to say "this wrapper does not own the QRhiTexture".
// createTextureFromRhiTexture() always claims ownership, and the engine's
// texture pool already has it.
#include <private/qsgplaintexture_p.h>
#include <QSGRendererInterface>
#include <rhi/qrhi.h>
#include <QTimer>
#include <QFileInfo>
#include <QFontDatabase>
#include <QStandardPaths>
#include <QRegularExpression>
#include "asset_paths.hpp"

// Only a dev fallback; the shipped app finds fonts beside the exe.
#ifndef RIFT_FONT_DIR
#define RIFT_FONT_DIR ""
#endif
#include <QProcess>
#include <QCoreApplication>
#include <QFile>
#include <QTextStream>
#include <QDateTime>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <mutex>
#include "engine.hpp"
#include "rhi_context.hpp"
#include "render_graph.hpp"
#include "parameter_graph.hpp"

// The audio channels a uniform can be driven from. Order MUST match the
// rift_channel enum and rift_channel_frame::ch[] - the index IS the binding.
// `key` is the wire name used in manifests; `name` is what the rack shows.
// Keyframes live on the engine-side Param. The UI model only carries a count
// and a "keyed at the playhead" flag, so the list is never duplicated.
namespace {
constexpr double kKeyEpsilon = 0.05;   // seconds; a key this close is "here"

int nearestKey(const std::vector<rift::Keyframe>& keys, double t) {
    int best = -1;
    double bestD = kKeyEpsilon;
    for (int i = 0; i < int(keys.size()); ++i) {
        const double d = std::abs(keys[i].time - t);
        if (d <= bestD) { bestD = d; best = i; }
    }
    return best;
}
} // namespace

struct ChannelDef { const char* key; const char* name; const char* note; };
static const ChannelDef kChannels[] = {
    { "bass",      "BASS",      "20-250 Hz low end"      },
    { "melody",    "MIDS",      "250-2k melodic body"    },
    { "highs",     "HIGHS",     "2-20k air / cymbals"    },
    { "drums",     "DRUMS",     "percussive energy"      },
    { "transient", "TRANSIENT", "onset hits"             },
    { "bpm",       "BPM",       "tempo, constant"        },
    { "centroid",  "CENTROID",  "spectral brightness"    },
    { "time",      "TIME",      "playhead ramp 0-1"      },
    { "kick",      "KICK",      "<150 Hz drum onset"     },
    { "snare",     "SNARE",     "1.5-8k drum onset"      },
};
static_assert(sizeof(kChannels) / sizeof(*kChannels) == RIFT_CH_COUNT,
              "channel table must match rift_channel");

// Manifest binding names -> channel index. "none"/unknown means static.
static int channelIndexOf(const QString& key) {
    for (int i = 0; i < RIFT_CH_COUNT; ++i)
        if (key.compare(QLatin1String(kChannels[i].key), Qt::CaseInsensitive) == 0)
            return i;
    return -1;
}

QVariantList RiftViewport::channelNames() const {
    QVariantList out;
    for (int i = 0; i < RIFT_CH_COUNT; ++i) {
        QVariantMap m;
        m[QStringLiteral("index")] = i;
        m[QStringLiteral("key")]   = QLatin1String(kChannels[i].key);
        m[QStringLiteral("name")]  = QLatin1String(kChannels[i].name);
        m[QStringLiteral("note")]  = QLatin1String(kChannels[i].note);
        out.append(m);
    }
    return out;
}

struct RiftViewport::Priv {
    std::unique_ptr<rift::Engine> engine;
    rift::TexId scene = 0;
    // Scene TexId the node's current QSGTexture wraps, 0 = none. Deliberately
    // an id and NOT a QSGTexture*: the node owns the wrapper and destroys it,
    // so any pointer we kept here dangled the moment the node went away - and
    // handing that freed pointer back to setTexture() double-deleted it.
    rift::TexId sg_scene = 0;
    QSize       size;
    bool        failed = false;
    QTimer      tick;                  // GUI thread: drives continuous frames
    int         ticks = 0;
    // The Engine is built lazily on the render thread, so a load requested
    // before the first frame would otherwise be dropped. Remember and replay.
    QString     pending_media_path, pending_audio_path, pending_analysis_path;
    bool        pending_live = false, pending_live_set = false;
    bool        replayed = false;

    // One entry per effect in the chain, in render order.
    struct Node {
        QString                  effect;
        std::vector<rift::Param> params;   // engine-side, layout order
        QVariantList             ui;       // manifest metadata for the panel
        uint32_t                 gid = 0;  // RenderGraph node id
        // How this effect folds over its own input. Normal+1 = plain replace.
        int   blend = rift::Blend_Normal;
        float mix   = 1.f;
    };

    // Chain edited on the GUI thread, consumed on the render thread. Guarded
    // rather than posted: it is tiny and read once per frame.
    std::mutex        params_mu;
    std::vector<Node> chain;
    // The shared chain, parked while the rail is editing a CLIP's own stack.
    // selectClip() overwrites `chain` with the clip's passes, and without
    // somewhere to put the shared one it was simply destroyed: going back to
    // the shared view (-1) then showed the clip's stack AS the shared chain,
    // and the next save wrote it as such.
    std::vector<Node> shared_chain;
    bool              shared_parked = false;
    bool              params_dirty = false;   // values only -> setParams
    bool              chain_dirty  = true;    // structure -> rebuild + build

    // Offscreen export engine (own QRhi + own render thread).
    std::unique_ptr<rift::Engine> export_engine;
    QString    export_out;
    QByteArray export_out_utf8, export_audio_utf8;   // spec holds raw pointers
    QByteArray export_font_utf8;
};

RiftViewport::RiftViewport(QQuickItem* parent)
    : QQuickItem(parent), d_(std::make_unique<Priv>()) {
    setFlag(ItemHasContents, true);

    // Frames must be requested from the GUI thread: QQuickItem::update() only
    // schedules a sync from there, so calling it inside beforeRendering (render
    // thread) silently does nothing and the scene renders exactly once. The
    // prototype drove its viewport off a 16 ms QTimer for the same reason.
    // Slider echo for external controllers, coalesced to ~20 Hz. Single-shot:
    // onControl_ restarts it, so a knob sweep emits once per 50 ms.
    control_ui_timer_.setInterval(50);
    control_ui_timer_.setSingleShot(true);
    connect(&control_ui_timer_, &QTimer::timeout, this,
            [this]{ emit controlValuesChanged(); });

    d_->tick.setInterval(16);
    connect(&d_->tick, &QTimer::timeout, this, [this]{
        if (qEnvironmentVariableIsSet("RIFT_UI_DBG") && ++d_->ticks % 60 == 0)
            fprintf(stderr, "[RiftViewport] tick %d (w=%.0f h=%.0f)\n",
                    d_->ticks, width(), height()), fflush(stderr);
        // Exactly ONE update source. Driving both item update() and
        // window->update() while also re-requesting a frame from frameSwapped
        // wedges the render loop: each mechanism works alone, together they
        // deadlock the scene after the first frame.
        update();
        pollEngine_();
    });
    initVisualizerStyles_();
    d_->tick.start();
}

RiftViewport::~RiftViewport() = default;

void RiftViewport::setShaderDir(const QString& s) {
    if (shader_dir_ == s) return;
    shader_dir_ = s;
    emit shaderDirChanged();
    // Manifests live beside the shaders, so the chain can only be described
    // once the directory is known. Seed a default node if empty.
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (d_->chain.empty()) {
            d_->chain.push_back({ QStringLiteral("ascii"), {}, {}, 0 });
            selected_ = 0;
        }
    }
    for (int i = 0; i < int(d_->chain.size()); ++i) loadManifest_(i);
    loadGradeManifest_();        // the grade manifest sits beside the shaders
    { std::lock_guard<std::mutex> lk(d_->params_mu); d_->chain_dirty = true; }
    syncChainToClip_();          // chain edits reach the engine via ClipSpec
    publishParams_();
    emit chainChanged();
    emit effectChanged();
    update();
}

QString RiftViewport::effect() const {
    std::lock_guard<std::mutex> lk(d_->params_mu);
    if (selected_ < 0 || selected_ >= int(d_->chain.size())) return {};
    return d_->chain[selected_].effect;
}

void RiftViewport::setEffect(const QString& e) {
    {
        // Bail out before pushing undo if nothing would change, otherwise the
        // stack fills with no-op steps.
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (!d_->chain.empty() && selected_ >= 0
            && selected_ < int(d_->chain.size())
            && d_->chain[selected_].effect == e) return;
    }
    pushUndo_(QStringLiteral("effect ") + e, QStringLiteral("setEffect"));
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (d_->chain.empty()) d_->chain.push_back({});
        if (selected_ < 0 || selected_ >= int(d_->chain.size())) selected_ = 0;
        if (d_->chain[selected_].effect == e) return;
        d_->chain[selected_].effect = e;
    }
    loadManifest_(selected_);       // different effect => different uniforms
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        d_->chain_dirty = true;
    }
    // A clip renders through ITS OWN ClipSpec::chain, so a chain edit that does
    // not mirror into it never reaches the engine. Without this, swapping the
    // effect on a selected clip changed the rail and nothing else, until some
    // later edit happened to sync it.
    syncChainToClip_();
    emit effectChanged();
    emit chainChanged();
    publishParams_();
    update();
}

QVariantList RiftViewport::chain() const {
    std::lock_guard<std::mutex> lk(d_->params_mu);
    QVariantList out;
    for (int i = 0; i < int(d_->chain.size()); ++i) {
        QVariantMap m;
        m[QStringLiteral("index")]    = i;
        m[QStringLiteral("effect")]   = d_->chain[i].effect;
        m[QStringLiteral("label")]    = d_->chain[i].effect.toUpper();
        m[QStringLiteral("params")]   = int(d_->chain[i].ui.size());
        m[QStringLiteral("selected")] = (i == selected_);
        m[QStringLiteral("blend")]    = d_->chain[i].blend;
        m[QStringLiteral("mix")]      = double(d_->chain[i].mix);
        out.append(m);
    }
    return out;
}

void RiftViewport::setSelectedNode(int i) {
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (i < 0 || i >= int(d_->chain.size()) || i == selected_) return;
        selected_ = i;
    }
    publishParams_();
    emit chainChanged();
    emit effectChanged();
}

void RiftViewport::addNode(const QString& effect) {
    pushUndo_(QStringLiteral("add ") + effect, QStringLiteral("addNode"));
    int idx;
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        d_->chain.push_back({ effect, {}, {}, 0 });
        idx = int(d_->chain.size()) - 1;
        selected_ = idx;
    }
    loadManifest_(idx);
    { std::lock_guard<std::mutex> lk(d_->params_mu); d_->chain_dirty = true; }
    syncChainToClip_();          // chain edits reach the engine via ClipSpec
    publishParams_();
    emit chainChanged();
    emit effectChanged();
    update();
}

void RiftViewport::removeNode(int index) {
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (index < 0 || index >= int(d_->chain.size())) return;
        if (d_->chain.size() <= 1) return;     // keep at least one effect
    }
    pushUndo_(QStringLiteral("remove node"), QStringLiteral("removeNode"));
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        d_->chain.erase(d_->chain.begin() + index);
        if (selected_ >= int(d_->chain.size())) selected_ = int(d_->chain.size()) - 1;
        // A control binding names its target by node INDEX, and erasing a node
        // shifts every later index down by one. Left alone, deleting an effect
        // pointed every knob above it at the wrong effect - silently, since
        // onControl_ only range-checks. Drop the dead binding, shift the rest.
        for (auto it = control_map_.begin(); it != control_map_.end(); ) {
            if (it->node == index) {
                it = control_map_.erase(it);
            } else {
                if (it->node > index) --it->node;
                ++it;
            }
        }
        d_->chain_dirty = true;
    }
    syncChainToClip_();          // chain edits reach the engine via ClipSpec
    publishParams_();
    emit chainChanged();
    emit effectChanged();
    update();
}

void RiftViewport::moveNode(int index, int delta) {
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        const int to = index + delta;
        if (index < 0 || index >= int(d_->chain.size())) return;
        if (to < 0 || to >= int(d_->chain.size())) return;
    }
    pushUndo_(QStringLiteral("reorder chain"), QStringLiteral("moveNode"));
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        const int to = index + delta;
        std::swap(d_->chain[index], d_->chain[to]);
        if (selected_ == index) selected_ = to;
        else if (selected_ == to) selected_ = index;
        // Bindings address a node by index, so they have to follow the swap or
        // reordering the chain hands each knob the other effect's parameter.
        for (auto it = control_map_.begin(); it != control_map_.end(); ++it) {
            if (it->node == index)   it->node = to;
            else if (it->node == to) it->node = index;
        }
        d_->chain_dirty = true;
    }
    syncChainToClip_();
    publishParams_();
    emit chainChanged();
    update();
}

// Recompute "is each parameter keyed at the playhead" and signal only when it
// actually changes. Deliberately NOT part of the params model: that model
// backs a ListView, and touching it every frame rebuilt every delegate.
int RiftViewport::keyAtPlayhead_(const std::vector<rift::Keyframe>& keys) const {
    const int at = nearestKey(keys, playhead_);
    if (at >= 0) return at;
    return nearestKey(keys, snapTime(playhead_));
}

void RiftViewport::refreshKeyState_() {
    QVariantList next;
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (selected_ >= 0 && selected_ < int(d_->chain.size()))
            for (const auto& p : d_->chain[selected_].params)
                next.append(keyAtPlayhead_(p.keys) >= 0);
    }
    if (next != keyed_now_) {
        keyed_now_ = std::move(next);
        emit keyStateChanged();
    }
}

// Interpolation of the key at the playhead, per parameter (-1 = none there).
// Same reasoning as keyedNow: time-varying, so kept out of the params model.
QVariantList RiftViewport::keyInterpNow() const {
    QVariantList out;
    std::lock_guard<std::mutex> lk(d_->params_mu);
    if (selected_ < 0 || selected_ >= int(d_->chain.size())) return out;
    for (const auto& p : d_->chain[selected_].params) {
        const int at = keyAtPlayhead_(p.keys);
        out.append(at >= 0 ? p.keys[at].interp : -1);
    }
    return out;
}

void RiftViewport::publishParams_() {
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        params_ui_ = (selected_ >= 0 && selected_ < int(d_->chain.size()))
                   ? d_->chain[selected_].ui : QVariantList{};

        // Only the key COUNT goes in the params model - it changes when the
        // user edits keys, not as time passes. "Keyed right now" and its
        // interpolation live in keyedNow/keyInterpNow, which do not reset the
        // ListView.
        if (selected_ >= 0 && selected_ < int(d_->chain.size())) {
            const auto& ps = d_->chain[selected_].params;
            for (int i = 0; i < params_ui_.size() && i < int(ps.size()); ++i) {
                QVariantMap m = params_ui_.at(i).toMap();
                m[QStringLiteral("keyCount")] = int(ps[i].keys.size());
                params_ui_[i] = m;
            }
        }
    }
    emit paramsChanged();
}

struct CachedManifest {
    QVariantList ui;
    std::vector<rift::Param> params;
};
static std::unordered_map<std::string, CachedManifest> s_manifestCache;

// Reads <effect>.manifest.json next to the .qsb files. Generated from the
// prototype by tools/gen_manifests.py, so labels/ranges/defaults match the
// Python app exactly rather than being re-guessed here.
void RiftViewport::loadManifest_(int nodeIndex) {
    QString fx;
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (nodeIndex < 0 || nodeIndex >= int(d_->chain.size())) return;
        fx = d_->chain[nodeIndex].effect;
    }

    const std::string fxKey = fx.toStdString();
    auto it = s_manifestCache.find(fxKey);
    if (it != s_manifestCache.end()) {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (nodeIndex < int(d_->chain.size())) {
            d_->chain[nodeIndex].params = it->second.params;
            d_->chain[nodeIndex].ui     = it->second.ui;
            d_->params_dirty = true;
        }
        return;
    }

    QVariantList ui;
    std::vector<rift::Param> engineParams;

    const QString path = QDir(shader_dir_).filePath(fx + ".manifest.json");
    QFile f(path);
    if (f.open(QIODevice::ReadOnly)) {
        const QJsonObject root = QJsonDocument::fromJson(f.readAll()).object();
        const QJsonArray uniforms = root.value(QStringLiteral("uniforms")).toArray();
        for (const QJsonValue& uv : uniforms) {
            const QJsonObject u = uv.toObject();
            const double def = u.value(QStringLiteral("default")).toDouble();
            const double mn  = u.value(QStringLiteral("min")).toDouble(0.0);
            const double mx  = u.value(QStringLiteral("max")).toDouble(1.0);

            // Default patch-bay binding, straight from the prototype's tables.
            const QJsonObject b = u.value(QStringLiteral("binding")).toObject();
            const int   chan  = b.isEmpty() ? -1
                              : channelIndexOf(b.value(QStringLiteral("channel")).toString());
            const double depth = b.value(QStringLiteral("depth")).toDouble(0.0);

            QVariantMap m;
            m[QStringLiteral("name")]  = u.value(QStringLiteral("name")).toString();
            m[QStringLiteral("label")] = u.value(QStringLiteral("label")).toString();
            m[QStringLiteral("min")]   = mn;
            m[QStringLiteral("max")]   = mx;
            m[QStringLiteral("step")]  = u.value(QStringLiteral("step")).toDouble(0.01);
            m[QStringLiteral("discrete")] = u.value(QStringLiteral("discrete")).toBool();
            m[QStringLiteral("value")] = def;
            m[QStringLiteral("default")] = def;
            m[QStringLiteral("channel")] = chan;
            m[QStringLiteral("depth")]   = depth;
            m[QStringLiteral("depthMax")] = mx - mn;      // full-range sweep
            ui.append(m);

            rift::Param p{};
            p.value = float(def);
            p.min_v = float(mn);
            p.max_v = float(mx);
            p.step  = float(u.value(QStringLiteral("step")).toDouble(0.01));
            p.discrete = u.value(QStringLiteral("discrete")).toBool();
            p.bind.channel = chan;                       // -1 = static
            p.bind.depth   = float(depth);
            p.bind.in_lo   = float(b.value(QStringLiteral("in_lo")).toDouble(0.0));
            p.bind.in_hi   = float(b.value(QStringLiteral("in_hi")).toDouble(1.0));
            p.bind.attack  = float(b.value(QStringLiteral("attack")).toDouble(0.0));
            p.bind.release = float(b.value(QStringLiteral("release")).toDouble(0.0));
            p.bind.invert  = b.value(QStringLiteral("invert")).toBool() ? 1 : 0;
            const QString curve = b.value(QStringLiteral("curve")).toString();
            p.bind.curve = curve == QLatin1String("exp") ? RIFT_CURVE_EXP
                         : curve == QLatin1String("log") ? RIFT_CURVE_LOG
                                                         : RIFT_CURVE_LIN;
            engineParams.push_back(p);
        }
        s_manifestCache[fxKey] = { ui, engineParams };
    } else {
        qWarning("RiftViewport: no manifest for '%s' at %s",
                 qPrintable(fx), qPrintable(path));
    }

    std::lock_guard<std::mutex> lk(d_->params_mu);
    if (nodeIndex < int(d_->chain.size())) {
        d_->chain[nodeIndex].params = std::move(engineParams);
        d_->chain[nodeIndex].ui     = std::move(ui);
        d_->params_dirty = true;
    }
}

// ── project / preset serialisation (project_format.md v3) ─────────────────
namespace {

const char* curveName(int c) {
    return c == RIFT_CURVE_EXP ? "exp" : (c == RIFT_CURVE_LOG ? "log" : "lin");
}
rift_curve curveFromName(const QString& s) {
    if (s == QLatin1String("exp")) return RIFT_CURVE_EXP;
    if (s == QLatin1String("log")) return RIFT_CURVE_LOG;
    return RIFT_CURVE_LIN;
}

// Ranges are deliberately NOT written: they come from the shader manifest on
// load, so editing a manifest updates existing projects instead of being
// overridden by a stale copy baked into the file.
QJsonObject paramToJson(const rift::Param& p) {
    QJsonObject o;
    o[QStringLiteral("value")]   = double(p.value);
    o[QStringLiteral("channel")] = p.bind.channel;
    o[QStringLiteral("depth")]   = double(p.bind.depth);
    o[QStringLiteral("curve")]   = QLatin1String(curveName(p.bind.curve));
    o[QStringLiteral("attack")]  = double(p.bind.attack);
    o[QStringLiteral("release")] = double(p.bind.release);
    o[QStringLiteral("in_lo")]   = double(p.bind.in_lo);
    o[QStringLiteral("in_hi")]   = double(p.bind.in_hi);
    o[QStringLiteral("invert")]  = p.bind.invert != 0;
    if (!p.keys.empty()) {
        QJsonArray keys;
        for (const auto& k : p.keys) {
            QJsonObject j;
            j[QStringLiteral("t")] = k.time;
            j[QStringLiteral("v")] = double(k.value);
            j[QStringLiteral("i")] = k.interp;
            keys.append(j);
        }
        o[QStringLiteral("keys")] = keys;
    }
    return o;
}

// Applies onto a param that already carries its manifest ranges.
void paramFromJson(const QJsonObject& o, rift::Param& p) {
    p.value = float(o.value(QStringLiteral("value")).toDouble(p.value));
    p.bind.channel = o.value(QStringLiteral("channel")).toInt(-1);
    p.bind.depth   = float(o.value(QStringLiteral("depth")).toDouble(0.0));
    p.bind.curve   = curveFromName(o.value(QStringLiteral("curve")).toString());
    p.bind.attack  = float(o.value(QStringLiteral("attack")).toDouble(0.0));
    p.bind.release = float(o.value(QStringLiteral("release")).toDouble(0.0));
    p.bind.in_lo   = float(o.value(QStringLiteral("in_lo")).toDouble(0.0));
    p.bind.in_hi   = float(o.value(QStringLiteral("in_hi")).toDouble(1.0));
    p.bind.invert  = o.value(QStringLiteral("invert")).toBool() ? 1 : 0;
    p.env = 0.f;

    p.keys.clear();
    for (const QJsonValue& kv : o.value(QStringLiteral("keys")).toArray()) {
        const QJsonObject k = kv.toObject();
        rift::Keyframe key;
        key.time   = k.value(QStringLiteral("t")).toDouble();
        key.value  = float(k.value(QStringLiteral("v")).toDouble());
        key.interp = k.value(QStringLiteral("i")).toInt(0);
        p.keys.push_back(key);
    }
    std::sort(p.keys.begin(), p.keys.end(),
              [](const rift::Keyframe& a, const rift::Keyframe& b) {
                  return a.time < b.time;
              });
}

} // namespace

// The grade is a fixed set of uniforms described by its own manifest, so it
// reuses the manifest reader's shape without joining the effect chain.
void RiftViewport::loadGradeManifest_() {
    grade_ui_.clear();
    grade_params_.clear();

    QFile f(QDir(shader_dir_).filePath(QStringLiteral("color_grade.manifest.json")));
    if (!f.open(QIODevice::ReadOnly)) {
        qWarning("RiftViewport: color_grade.manifest.json not found");
        return;
    }
    const QJsonObject root = QJsonDocument::fromJson(f.readAll()).object();
    for (const QJsonValue& uv : root.value(QStringLiteral("uniforms")).toArray()) {
        const QJsonObject u = uv.toObject();
        const double def = u.value(QStringLiteral("default")).toDouble();
        const double mn  = u.value(QStringLiteral("min")).toDouble(0.0);
        const double mx  = u.value(QStringLiteral("max")).toDouble(1.0);

        QVariantMap m;
        m[QStringLiteral("name")]    = u.value(QStringLiteral("name")).toString();
        m[QStringLiteral("label")]   = u.value(QStringLiteral("label")).toString();
        m[QStringLiteral("min")]     = mn;
        m[QStringLiteral("max")]     = mx;
        m[QStringLiteral("step")]    = u.value(QStringLiteral("step")).toDouble(0.01);
        m[QStringLiteral("value")]   = def;
        m[QStringLiteral("default")] = def;
        // Patch-bay fields, same shape the effect params publish, so the grade
        // can drive PatchRow without a second kind of model.
        m[QStringLiteral("channel")]  = -1;
        m[QStringLiteral("depth")]    = 0.0;
        m[QStringLiteral("depthMax")] = mx - mn;
        m[QStringLiteral("keyCount")] = 0;
        grade_ui_.append(m);

        rift::Param p{};
        p.value = float(def);
        p.min_v = float(mn);
        p.max_v = float(mx);
        p.step  = float(u.value(QStringLiteral("step")).toDouble(0.01));
        p.bind.channel = -1;
        grade_params_.push_back(p);
    }
    pushGrade_();
}

// grade_params_ is authoritative; this republishes what QML reads off it.
void RiftViewport::publishGrade_() {
    for (int i = 0; i < grade_ui_.size() && i < int(grade_params_.size()); ++i) {
        const rift::Param& p = grade_params_[i];
        QVariantMap m = grade_ui_.at(i).toMap();
        m[QStringLiteral("value")]    = double(p.value);
        m[QStringLiteral("channel")]  = p.bind.channel;
        m[QStringLiteral("depth")]    = double(p.bind.depth);
        m[QStringLiteral("keyCount")] = int(p.keys.size());
        grade_ui_[i] = m;
    }
    pushGrade_();
}

void RiftViewport::refreshGradeKeyState_() {
    QVariantList next;
    for (const auto& p : grade_params_)
        next.append(keyAtPlayhead_(p.keys) >= 0);
    if (next != grade_keyed_now_) {
        grade_keyed_now_ = std::move(next);
        emit gradeKeyStateChanged();
    }
}

QVariantList RiftViewport::gradeKeyInterpNow() const {
    QVariantList out;
    for (const auto& p : grade_params_) {
        const int at = keyAtPlayhead_(p.keys);
        out.append(at >= 0 ? p.keys[at].interp : -1);
    }
    return out;
}

void RiftViewport::setGradeBinding(int index, int channel, qreal depth) {
    if (index < 0 || index >= int(grade_params_.size())) return;
    if (channel >= RIFT_CH_COUNT) return;
    pushUndo_(QStringLiteral("grade patch"),
              QStringLiteral("gradePatch:%1").arg(index));
    rift::Param& p = grade_params_[index];
    p.bind.channel = channel < 0 ? -1 : channel;
    p.bind.depth   = float(depth);
    p.env          = 0.f;            // no smear across a re-patch
    publishGrade_();          // pushes to the engine and emits gradeChanged
    update();
}

void RiftViewport::addGradeKey(int index) {
    if (index < 0 || index >= int(grade_params_.size())) return;
    pushUndo_(QStringLiteral("grade key"),
              QStringLiteral("gradeKey:%1").arg(index));
    const double t = snapTime(playhead_);       // snapped for PLACEMENT
    auto& keys = grade_params_[index].keys;
    const int at = keyAtPlayhead_(keys);        // but either time counts as "here"
    if (at >= 0) {
        keys[at].value = grade_params_[index].value;   // re-key in place
    } else {
        rift::Keyframe k;
        k.time  = t;
        k.value = grade_params_[index].value;
        keys.push_back(k);
        std::sort(keys.begin(), keys.end(),
                  [](const rift::Keyframe& a, const rift::Keyframe& b) {
                      return a.time < b.time;
                  });
    }
    publishGrade_();          // pushes to the engine and emits gradeChanged
    refreshGradeKeyState_();
    update();
}

void RiftViewport::removeGradeKeyAt(int index) {
    if (index < 0 || index >= int(grade_params_.size())) return;
    auto& keys = grade_params_[index].keys;
    const int at = keyAtPlayhead_(keys);
    if (at < 0) return;
    pushUndo_(QStringLiteral("grade key"),
              QStringLiteral("gradeKeyDel:%1").arg(index));
    keys.erase(keys.begin() + at);
    publishGrade_();          // pushes to the engine and emits gradeChanged
    refreshGradeKeyState_();
    update();
}

void RiftViewport::clearGradeKeys(int index) {
    if (index < 0 || index >= int(grade_params_.size())) return;
    if (grade_params_[index].keys.empty()) return;
    pushUndo_(QStringLiteral("clear grade keys"),
              QStringLiteral("gradeKeyClear:%1").arg(index));
    grade_params_[index].keys.clear();
    publishGrade_();          // pushes to the engine and emits gradeChanged
    refreshGradeKeyState_();
    update();
}

void RiftViewport::cycleGradeKeyInterp(int index) {
    if (index < 0 || index >= int(grade_params_.size())) return;
    auto& keys = grade_params_[index].keys;
    const int at = keyAtPlayhead_(keys);
    if (at < 0) return;
    pushUndo_(QStringLiteral("grade key interp"),
              QStringLiteral("gradeKeyInterp:%1").arg(index));
    keys[at].interp = (keys[at].interp + 1) % 3;   // linear -> ease -> step
    publishGrade_();          // pushes to the engine and emits gradeChanged
    refreshGradeKeyState_();
    update();
}

// Same bound as keyOnMarkers: the piece runs until both the picture and the
// music are done, and a key is read against the real playhead.
int RiftViewport::keyGradeOnMarkers(int index) {
    if (index < 0 || index >= int(grade_params_.size())) return 0;
    if (markers_.empty()) return 0;

    double reach = track_dur_;
    if (d_->engine) reach = std::max(reach, d_->engine->audioDuration());

    pushUndo_(QStringLiteral("grade keys on beats"),
              QStringLiteral("gradeBeats:%1").arg(index));

    const float v = grade_params_[index].value;
    auto& keys = grade_params_[index].keys;
    int n = 0;
    for (double t : markers_) {
        if (reach > 0.0 && t > reach) break;
        const int at = nearestKey(keys, t);
        if (at >= 0) {
            keys[at].value = v;
        } else {
            rift::Keyframe k;
            k.time  = t;
            k.value = v;
            keys.push_back(k);
        }
        ++n;
    }
    std::sort(keys.begin(), keys.end(),
              [](const rift::Keyframe& a, const rift::Keyframe& b) {
                  return a.time < b.time;
              });
    publishGrade_();          // pushes to the engine and emits gradeChanged
    refreshGradeKeyState_();
    update();
    return n;
}

void RiftViewport::pushGrade_() {
    if (d_->engine) d_->engine->setGrade(grade_params_);
    emit gradeChanged();
}

void RiftViewport::setGradeParam(int index, qreal value) {
    if (index < 0 || index >= grade_ui_.size()) return;
    pushUndo_(QStringLiteral("grade"), QStringLiteral("grade:%1").arg(index));
    QVariantMap m = grade_ui_.at(index).toMap();
    m[QStringLiteral("value")] = value;
    grade_ui_[index] = m;
    if (index < int(grade_params_.size()))
        grade_params_[index].value = float(value);
    // No gradeChanged() here - same reason setParam stays quiet: re-emitting
    // resets the sliders' model mid-drag.
    if (d_->engine) d_->engine->setGrade(grade_params_);
    update();
}

void RiftViewport::resetGrade() {
    pushUndo_(QStringLiteral("reset grade"), QStringLiteral("resetGrade"));
    for (int i = 0; i < grade_ui_.size(); ++i) {
        const QVariantMap m = grade_ui_.at(i).toMap();
        if (i >= int(grade_params_.size())) continue;
        rift::Param& p = grade_params_[i];
        p.value = float(m.value(QStringLiteral("default")).toDouble());
        // Patches and keys go too. Now that the grade can be driven by audio or
        // animated, a reset that only restored VALUES would leave the picture
        // still moving while every slider sat at its default - and the panel's
        // "graded" hint compares values, so it would read as untouched.
        p.bind.channel = -1;
        p.bind.depth   = 0.f;
        p.env          = 0.f;
        p.keys.clear();
    }
    publishGrade_();          // pushes to the engine and emits gradeChanged
    refreshGradeKeyState_();
    update();
}

void RiftViewport::setMode(int m) {
    const int v = (m == 1) ? 1 : 0;
    if (mode_ == v) return;
    mode_ = v;
    // One sound source at a time. Live listens to whatever this machine is
    // playing; with the project track still running you hear both at once, and
    // RIFT ends up reacting to its own output through the loopback.
    if (v == 1 && playing_) pause();
    if (v == 0 && live_input_) setLiveInput(false);
    emit modeChanged();
}

QString RiftViewport::projectName() const {
    // Shown in the window title. The extension is noise there - the task bar
    // has limited room and ".rt" tells the user nothing they did not choose.
    if (!project_path_.isEmpty()) return QFileInfo(project_path_).completeBaseName();
    return project_title_.isEmpty() ? QStringLiteral("Untitled") : project_title_;
}

// ── text layers ───────────────────────────────────────────────────────────
// Defaults to lane 1 and a fixed span: text is almost always laid OVER footage,
// and it has no source whose length could be measured.
void RiftViewport::addTextClip(const QString& text, int lane, qreal seconds) {
    pushUndo_(QStringLiteral("add text"), QStringLiteral("addText"));

    rift::ClipSpec c;
    c.kind  = rift::ClipSpec::Text;
    c.lane  = std::max(0, lane);
    // -1 = "append after the previous clip IN THIS LANE", as addClip does. At a
    // fixed 0 the first caption was fine and every one after it landed exactly
    // on top of it, on the same lane, where it read as nothing happening.
    c.start = -1.0;
    c.in    = 0.0;
    c.out   = std::max(0.1, double(seconds));   // its own span, no source to ask
    c.text.text = text.toStdString();
    // Screen, not Normal: text over footage should read as light on the image
    // rather than punching a hole in it. Overridable per clip like any other.
    c.blend = rift::Blend_Screen;
    clip_specs_.push_back(c);

    has_media_ = true;
    pushClips_();
    emit sourceChanged();
    update();
}

void RiftViewport::setClipText(int index, const QString& text) {
    if (index < 0 || index >= int(clip_specs_.size())) return;
    if (clip_specs_[index].kind != rift::ClipSpec::Text) return;
    // Tagged per clip so typing a caption is one undo step, not one per letter.
    pushUndo_(QStringLiteral("edit text"),
              QStringLiteral("clipText:%1").arg(index));
    clip_specs_[index].text.text = text.toStdString();
    pushClips_();
    update();
}

void RiftViewport::setClipTextStyle(int index, qreal size, qreal x, qreal y,
                                    qreal r, qreal g, qreal b, bool bold,
                                    qreal letterSpacing, qreal wrapWidth,
                                    const QString& font) {
    if (index < 0 || index >= int(clip_specs_.size())) return;
    if (clip_specs_[index].kind != rift::ClipSpec::Text) return;
    pushUndo_(QStringLiteral("text style"),
              QStringLiteral("clipTextStyle:%1").arg(index));

    auto& t = clip_specs_[index].text;
    t.size = qBound(0.01, double(size), 2.0);
    t.x    = qBound(-1.0, double(x), 2.0);
    t.y    = qBound(-1.0, double(y), 2.0);
    t.r    = float(qBound(0.0, double(r), 1.0));
    t.g    = float(qBound(0.0, double(g), 1.0));
    t.b    = float(qBound(0.0, double(b), 1.0));
    t.bold = bold;
    t.letterSpacing = qBound(-50.0, double(letterSpacing), 200.0);
    t.wrapWidth     = qBound(0.0, double(wrapWidth), 1.0);
    // A null QString means "leave it alone", so callers that only want to move
    // the text do not have to know the family name to keep it.
    if (!font.isNull()) t.font = font.toStdString();
    pushClips_();
    update();
}

void RiftViewport::restartApp() {
    // Start the replacement before quitting: after quit() returns there is no
    // event loop left to launch anything from.
    QProcess::startDetached(QCoreApplication::applicationFilePath(),
                            QCoreApplication::arguments().mid(1));
    QCoreApplication::quit();
}

// Mark in / out. Setting one does not disturb the other unless it would make
// the range inside-out, which is easier to reason about than silently swapping
// them under the user.
void RiftViewport::setMarkIn(double t) {
    mark_in_ = std::max(0.0, t);
    if (mark_out_ > 0.0 && mark_out_ <= mark_in_) mark_out_ = 0.0;
    emit marksChanged();
}

void RiftViewport::setMarkOut(double t) {
    mark_out_ = std::max(0.0, t);
    if (mark_out_ <= mark_in_) mark_in_ = 0.0;
    emit marksChanged();
}

void RiftViewport::clearMarks() {
    mark_in_ = mark_out_ = 0.0;
    emit marksChanged();
}

QStringList RiftViewport::systemFonts() const {
    // Includes the app's bundled families: main_qml registers them with
    // QFontDatabase at startup, so they come back from the same query.
    QStringList f = QFontDatabase::families();
    f.removeDuplicates();
    return f;
}

QVariantMap RiftViewport::clipText(int index) const {
    QVariantMap m;
    if (index < 0 || index >= int(clip_specs_.size())) return m;
    const auto& c = clip_specs_[index];
    m[QStringLiteral("isText")] = (c.kind == rift::ClipSpec::Text);
    const auto& t = c.text;
    m[QStringLiteral("text")] = QString::fromStdString(t.text);
    m[QStringLiteral("font")] = QString::fromStdString(t.font);
    m[QStringLiteral("size")] = t.size;
    m[QStringLiteral("x")]    = t.x;
    m[QStringLiteral("y")]    = t.y;
    m[QStringLiteral("r")]    = double(t.r);
    m[QStringLiteral("g")]    = double(t.g);
    m[QStringLiteral("b")]    = double(t.b);
    m[QStringLiteral("bold")] = t.bold;
    m[QStringLiteral("letterSpacing")] = t.letterSpacing;
    m[QStringLiteral("wrapWidth")]     = t.wrapWidth;
    return m;
}

// ── beat / onset markers ──────────────────────────────────────────────────
void RiftViewport::publishMarkers_() {
    std::sort(markers_.begin(), markers_.end());
    markers_ui_.clear();
    markers_ui_.reserve(int(markers_.size()));
    for (double t : markers_) markers_ui_.append(t);
    emit markersChanged();
}

void RiftViewport::setSnapToMarkers(bool on) {
    if (snap_ == on) return;
    snap_ = on;
    emit markersChanged();
}

// Binary search rather than a scan: a five-minute track can carry hundreds of
// markers and this runs on every drag event.
qreal RiftViewport::snapTime(qreal t, qreal tolerance) const {
    if (!snap_ || markers_.empty()) return t;
    const auto it = std::lower_bound(markers_.begin(), markers_.end(), double(t));
    double best = t;
    double bestDist = tolerance;
    if (it != markers_.end() && std::abs(*it - t) <= bestDist) {
        best = *it; bestDist = std::abs(*it - t);
    }
    if (it != markers_.begin()) {
        const double prev = *(it - 1);
        if (std::abs(prev - t) <= bestDist) best = prev;
    }
    return best;
}

void RiftViewport::addMarker(qreal t) {
    if (t < 0.0) return;
    markers_.push_back(double(t));
    markers_edited_ = true;
    publishMarkers_();
}

void RiftViewport::removeMarkerNear(qreal t, qreal tolerance) {
    if (markers_.empty()) return;
    size_t best = markers_.size();
    double bestDist = tolerance;
    for (size_t i = 0; i < markers_.size(); ++i) {
        const double d = std::abs(markers_[i] - t);
        if (d <= bestDist) { bestDist = d; best = i; }
    }
    if (best == markers_.size()) return;
    markers_.erase(markers_.begin() + best);
    markers_edited_ = true;
    publishMarkers_();
}

void RiftViewport::clearMarkers() {
    markers_.clear();
    markers_edited_ = true;
    publishMarkers_();
}

void RiftViewport::detectMarkers() {
    if (!d_->engine) return;
    const std::vector<double> bt = d_->engine->beats();
    markers_.assign(bt.begin(), bt.end());
    bpm_ = double(d_->engine->bpm());
    markers_edited_ = false;      // back to whatever the audio says
    publishMarkers_();
}

// The payoff for having markers: key a parameter on every beat in one action,
// instead of scrubbing to each one and pressing SET.
int RiftViewport::keyOnMarkers(int paramIndex) {
    if (markers_.empty()) return 0;

    // Value to record: whatever the parameter reads right now, so this repeats
    // the current look on each beat rather than inventing numbers.
    double v = 0.0;
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (selected_ < 0 || selected_ >= int(d_->chain.size())) return 0;
        const auto& ps = d_->chain[selected_].params;
        if (paramIndex < 0 || paramIndex >= int(ps.size())) return 0;
        v = double(ps[paramIndex].value);
    }

    // The piece runs until BOTH the picture and the music are done, and a key
    // is evaluated against the real playhead - only the clip lookup wraps. So
    // the bound is the longer of the two: against track_dur_ alone, a 4 s loop
    // under a 2 minute song got keys on the first few beats and nothing after.
    double reach = track_dur_;
    if (d_->engine) reach = std::max(reach, d_->engine->audioDuration());

    int n = 0;
    for (double t : markers_) {
        if (reach > 0.0 && t > reach) break;
        addKeyAt(paramIndex, t, v, 0);
        ++n;
    }
    return n;
}

// ── per-effect layering ───────────────────────────────────────────────────
QStringList RiftViewport::blendNames() const {
    // Order must match rift::BlendMode / composite.frag.
    static const QStringList kNames{
        QStringLiteral("NORM"), QStringLiteral("ADD"),
        QStringLiteral("MULT"), QStringLiteral("SCRN"),
        QStringLiteral("DIFF"), QStringLiteral("OVER"),
        QStringLiteral("SUB") };
    return kNames;
}

void RiftViewport::setNodeBlend(int index, int blend, qreal mix) {
    pushUndo_(QStringLiteral("node blend"), QStringLiteral("nodeBlend:%1").arg(index));
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (index < 0 || index >= int(d_->chain.size())) return;
        d_->chain[index].blend =
            (blend >= 0 && blend < rift::Blend_Count) ? blend : rift::Blend_Normal;
        d_->chain[index].mix = float(std::clamp(double(mix), 0.0, 1.0));
        d_->chain_dirty = true;
    }
    syncChainToClip_();          // chain edits reach the engine via ClipSpec
    emit chainChanged();
    update();
}

void RiftViewport::cycleNodeBlend(int index) {
    int next = 0;
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (index < 0 || index >= int(d_->chain.size())) return;
        next = (d_->chain[index].blend + 1) % rift::Blend_Count;
    }
    // Mix is left alone: cycling modes should not silently undo a dialled-in
    // wet/dry setting.
    float keepMix = 1.f;
    { std::lock_guard<std::mutex> lk(d_->params_mu); keepMix = d_->chain[index].mix; }
    setNodeBlend(index, next, keepMix);
}

// ── external control ──────────────────────────────────────────────────────
void RiftViewport::ensureControl_() {
    if (control_) return;
    control_ = std::make_unique<ControlInput>(this);
    connect(control_.get(), &ControlInput::controlReceived,
            this, &RiftViewport::onControl_);
}

QStringList RiftViewport::midiDevices() const {
    const_cast<RiftViewport*>(this)->ensureControl_();
    return control_->midiDevices();
}
bool RiftViewport::openMidi(int deviceIndex) {
    ensureControl_();
    const bool ok = control_->openMidi(deviceIndex);
    last_control_ = ok ? QStringLiteral("MIDI open")
                       : QStringLiteral("MIDI open failed");
    emit controlChanged();
    return ok;
}
bool RiftViewport::connectController() {
    ensureControl_();
    const QStringList devs = control_->midiDevices();
    for (int i = 0; i < devs.size(); ++i) {
        const QString n = devs.at(i).toLower();
        if (n.contains(QLatin1String("wavetable"))
            || n.contains(QLatin1String("microsoft gs"))) continue;
        if (openMidi(i)) return true;
    }
    last_control_ = devs.isEmpty() ? QStringLiteral("no MIDI devices found")
                                   : QStringLiteral("could not open controller");
    emit controlChanged();
    return false;
}

void RiftViewport::closeMidi() {
    if (control_) control_->closeMidi();
    emit controlChanged();
}
bool RiftViewport::startOsc(int port) {
    ensureControl_();
    const bool ok = control_->startOsc(quint16(port));
    last_control_ = ok ? QStringLiteral("OSC :%1").arg(port)
                       : QStringLiteral("OSC port %1 busy").arg(port);
    emit controlChanged();
    return ok;
}
void RiftViewport::stopOsc() {
    if (control_) control_->stopOsc();
    emit controlChanged();
}
bool RiftViewport::midiOpen() const {
    return control_ && control_->openMidiIndex() >= 0;
}
bool RiftViewport::oscOpen() const {
    return control_ && control_->oscPort() != 0;
}

QString RiftViewport::midiName() const {
    return control_ ? control_->openMidiName() : QString();
}

// Flattened for the UI, with the node index so a mapping on a node you are
// not looking at is still visible.
QVariantList RiftViewport::allControls() const {
    QVariantList out;
    for (auto it = control_map_.cbegin(); it != control_map_.cend(); ++it) {
        QVariantMap m;
        m[QStringLiteral("key")]   = it.key();
        m[QStringLiteral("node")]  = it->node;
        m[QStringLiteral("param")] = it->param;
        QString label;
        {
            std::lock_guard<std::mutex> lk(d_->params_mu);
            if (it->node >= 0 && it->node < int(d_->chain.size())) {
                const auto& ui = d_->chain[it->node].ui;
                if (it->param >= 0 && it->param < ui.size())
                    label = ui.at(it->param).toMap()
                              .value(QStringLiteral("label")).toString();
                if (label.isEmpty())
                    label = d_->chain[it->node].effect;
            }
        }
        m[QStringLiteral("label")] = label;
        out.append(m);
    }
    return out;
}

// Hardware-first half of mapping. Arming a control and then pressing MAP on a
// parameter binds the pair without waiting for the knob to move again.
void RiftViewport::armControl(const QString& key) {
    armed_control_ = key;
    last_control_  = key.isEmpty() ? QString()
                                   : key + QStringLiteral(" -> pick a setting");
    emit controlChanged();
}

void RiftViewport::learnControl(int paramIndex) {
    // A control is already armed: bind now rather than asking the user to
    // touch the hardware a second time.
    if (paramIndex >= 0 && !armed_control_.isEmpty()) {
        mapControl(armed_control_, paramIndex);
        armed_control_.clear();
        learn_param_ = -1;
        emit controlChanged();
        return;
    }
    learn_param_ = paramIndex;
    last_control_ = paramIndex >= 0 ? QStringLiteral("move a control...")
                                    : QString();
    emit controlChanged();
}

void RiftViewport::mapControl(const QString& key, int paramIndex) {
    if (key.isEmpty() || paramIndex < 0) return;
    control_map_.insert(key, { selected_, paramIndex });
    if (qEnvironmentVariableIsSet("RIFT_DBG"))
        qInfo("[control] map %s -> node %d param %d",
              qPrintable(key), selected_, paramIndex);
    emit controlChanged();
}

void RiftViewport::clearControl(int paramIndex) {
    for (auto it = control_map_.begin(); it != control_map_.end(); ) {
        if (it->node == selected_ && it->param == paramIndex)
            it = control_map_.erase(it);
        else
            ++it;
    }
    emit controlChanged();
}

// Bindings are per (node, param) of the SELECTED node at learn time, so the
// same controller can drive different effects as you move through the chain.
QVariantList RiftViewport::allMappings() const {
    QVariantList out;
    std::lock_guard<std::mutex> lk(d_->params_mu);
    for (auto it = control_map_.cbegin(); it != control_map_.cend(); ++it) {
        const ControlTarget t = it.value();
        QVariantMap m;
        m[QStringLiteral("key")]   = it.key();
        m[QStringLiteral("node")]  = t.node;
        m[QStringLiteral("param")] = t.param;
        // Name the effect and parameter rather than printing two integers: a
        // list of "cc:74 -> 0/3" tells the reader nothing.
        QString effect, label;
        if (t.node >= 0 && t.node < int(d_->chain.size())) {
            const auto& n = d_->chain[t.node];
            effect = n.effect;
            // `ui` is the manifest metadata the panel renders from; rift::Param
            // carries only the numbers.
            if (t.param >= 0 && t.param < n.ui.size()) {
                const QVariantMap pm = n.ui[t.param].toMap();
                label = pm.value(QStringLiteral("label")).toString();
                if (label.isEmpty())
                    label = pm.value(QStringLiteral("name")).toString();
            }
        }
        m[QStringLiteral("effect")] = effect;
        m[QStringLiteral("label")]  = label;
        out.append(m);
    }
    return out;
}

void RiftViewport::clearMappingKey(const QString& key) {
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (control_map_.remove(key) == 0) return;
    }
    emit controlChanged();
}

QVariantList RiftViewport::controlMap() const {
    QVariantList out;
    int n = 0;
    { std::lock_guard<std::mutex> lk(d_->params_mu);
      if (selected_ >= 0 && selected_ < int(d_->chain.size()))
          n = int(d_->chain[selected_].params.size()); }
    for (int i = 0; i < n; ++i) {
        QString key;
        for (auto it = control_map_.cbegin(); it != control_map_.cend(); ++it)
            if (it->node == selected_ && it->param == i) { key = it.key(); break; }
        out.append(key);
    }
    return out;
}

// Values of the selected node, in `params` order. Empty means "no override" -
// QML falls back to the model's own value.
QVariantList RiftViewport::controlValues() const {
    QVariantList out;
    for (const QVariant& v : params_ui_)
        out.append(v.toMap().value(QStringLiteral("value")));
    return out;
}

void RiftViewport::onControl_(const QString& key, qreal value) {
    last_control_ = key + QStringLiteral(" ") + QString::number(value, 'f', 2);
    if (qEnvironmentVariableIsSet("RIFT_DBG"))
        qInfo("[control] %s = %.3f", qPrintable(key), value);

    if (learn_param_ >= 0) {
        control_map_.insert(key, { selected_, learn_param_ });
        learn_param_ = -1;
        emit controlChanged();
        return;                        // do not also move it on the learn event
    }

    const auto it = control_map_.constFind(key);
    if (it == control_map_.cend()) {
        // Unmapped: surface it so you can see traffic arriving before binding.
        emit controlChanged();
        return;
    }

    // Write straight into the chain rather than going through setParam: a
    // mapped knob must keep driving its node even while a DIFFERENT node is
    // selected, and setParam only ever touches the selected one.
    double v = 0.0;
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (it->node < 0 || it->node >= int(d_->chain.size())) return;
        auto& ps = d_->chain[it->node].params;
        if (it->param < 0 || it->param >= int(ps.size())) return;
        // Controllers send 0..1; map onto the parameter's own range so a knob
        // sweeps exactly what the slider does.
        auto& p = ps[it->param];
        v = p.min_v + value * (p.max_v - p.min_v);
        p.value = float(v);
        d_->params_dirty = true;
    }
    // Mirror into the visible rack only when that node is on screen, and let
    // the throttle timer tell QML about it.
    if (it->node == selected_ && it->param < params_ui_.size()) {
        QVariantMap m = params_ui_.at(it->param).toMap();
        m[QStringLiteral("value")] = v;
        params_ui_[it->param] = m;
        if (!control_ui_timer_.isActive()) control_ui_timer_.start();
    }
    if (qEnvironmentVariableIsSet("RIFT_DBG"))
        qInfo("[control] -> node %d param %d = %.3f", it->node, it->param, v);
    // No controlChanged/paramsChanged here: a knob sends ~100 msgs/s and
    // re-evaluating those bindings each time is the ListView-rebuild cost over
    // again. The value is live in the render chain regardless.
    syncChainToClip_();
    update();
}

void RiftViewport::newProject() {
    pushUndo_(QStringLiteral("new project"), QStringLiteral("new"));

    clip_specs_.clear();
    audio_clip_specs_.clear();
    audio_clips_ui_.clear();
    edited_clip_ = -1;
    markers_.clear();
    markers_edited_ = false;
    project_path_.clear();
    project_title_.clear();
    has_media_ = false;
    media_name_.clear();
    project_aspect_ = 0;
    d_->pending_media_path.clear();
    d_->pending_audio_path.clear();
    d_->pending_analysis_path.clear();

    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        d_->shared_chain.clear();      // nothing parked in an empty session
        d_->shared_parked = false;
        d_->chain.clear();
        d_->chain.push_back({ QStringLiteral("ascii"), {}, {}, 0 });
        selected_ = 0;
        d_->chain_dirty = true;
    }
    loadManifest_(0);
    loadGradeManifest_();          // grade back to neutral defaults
    pushGrade_();

    pushClips_();
    publishParams_();
    publishMarkers_();
    emit chainChanged();
    emit effectChanged();
    emit sourceChanged();
    emit projectChanged();
    update();
}

// ---- preset library ----

QVariantList RiftViewport::liveDevices() {
    QVariantList out;
    if (!d_->engine) return out;
    for (const auto& [name, loopback] : d_->engine->liveDevices()) {
        QVariantMap m;
        m[QStringLiteral("name")]     = QString::fromStdString(name);
        m[QStringLiteral("loopback")] = loopback;
        out.append(m);
    }
    return out;
}

void RiftViewport::setLiveDevice(int index) {
    if (index == live_device_) return;
    live_device_ = index;
    if (d_->engine) d_->engine->setLiveDevice(index);
    emit sourceChanged();
}

QString RiftViewport::presetsFolder() const {
    // AppDataLocation, not the executable's folder: an installed copy lives
    // under Program Files, which a normal user cannot write to.
    const QString base =
        QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    const QString dir = QDir(base).filePath(QStringLiteral("presets"));
    QDir().mkpath(dir);
    return dir;
}

QVariantList RiftViewport::presets() const {
    QVariantList out;
    QDir d(presetsFolder());
    const auto files = d.entryInfoList({ QStringLiteral("*.rt") },
                                       QDir::Files, QDir::Name);
    for (const QFileInfo& f : files) {
        QVariantMap m;
        m[QStringLiteral("name")] = f.completeBaseName();
        m[QStringLiteral("path")] = f.absoluteFilePath();
        out.append(m);
    }
    return out;
}

bool RiftViewport::savePresetNamed(const QString& name) {
    QString clean = name.trimmed();
    // Strip anything that cannot be a filename rather than failing on it: the
    // user typed a preset name, not a path.
    clean.remove(QRegularExpression(QStringLiteral("[\\\\/:*?\"<>|]")));
    if (clean.isEmpty()) { last_error_ = QStringLiteral("name is empty"); return false; }

    const QString path = QDir(presetsFolder()).filePath(clean + QStringLiteral(".rt"));
    // asProject=false is what makes this a preset: the look only, and the
    // session is NOT re-pointed at the file it just wrote.
    const bool ok = saveProject(QUrl::fromLocalFile(path), /*asProject=*/false);
    if (ok) emit presetsChanged();
    return ok;
}

// Apply a saved look over the current session, WITHOUT becoming that file.
//
// This used to be loadProject(), which set project_path_ to the preset. From
// then on the session was the preset: Save wrote to the library, so tweaking
// anything after applying a preset silently rewrote the preset itself. A preset
// is a starting point you edit away from - editing it must never travel back.
bool RiftViewport::applyPreset(const QString& path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        last_error_ = QStringLiteral("cannot read ") + path;
        emit projectChanged();
        return false;
    }
    const QJsonObject root = QJsonDocument::fromJson(f.readAll()).object();
    if (root.value(QStringLiteral("format")).toString()
        != QLatin1String("rift-project")) {
        last_error_ = QStringLiteral("not a rift preset");
        emit projectChanged();
        return false;
    }
    // Undoable like any other edit, so a preset can be tried and backed out of.
    pushUndo_(QStringLiteral("apply preset"), QStringLiteral("preset"));
    const bool ok = applyProjectJson_(root, /*asProject=*/false);
    clearRedo_();
    last_error_ = QStringLiteral("applied ") + QFileInfo(path).completeBaseName();
    emit projectChanged();
    return ok;
}

bool RiftViewport::deletePreset(const QString& path) {
    // Confined to the presets folder: applyPreset takes a path from the UI, and
    // delete should never be able to reach outside it.
    const QFileInfo f(path);
    if (f.absolutePath() != QFileInfo(presetsFolder()).absoluteFilePath()) {
        last_error_ = QStringLiteral("not a preset path");
        return false;
    }
    const bool ok = QFile::remove(path);
    if (ok) emit presetsChanged();
    return ok;
}

bool RiftViewport::renamePreset(const QString& oldPath, const QString& newName) {
    const QFileInfo f(oldPath);
    if (f.absolutePath() != QFileInfo(presetsFolder()).absoluteFilePath()) {
        last_error_ = QStringLiteral("not a preset path");
        return false;
    }
    QString clean = newName.trimmed();
    clean.remove(QRegularExpression(QStringLiteral("[\\\\/:*?\"<>|]")));
    if (clean.isEmpty()) { last_error_ = QStringLiteral("name is empty"); return false; }
    const QString newPath = QDir(presetsFolder()).filePath(clean + QStringLiteral(".rt"));
    if (QFile::exists(newPath)) {
        last_error_ = QStringLiteral("preset already exists");
        return false;
    }
    const bool ok = QFile::rename(oldPath, newPath);
    if (ok) emit presetsChanged();
    return ok;
}

bool RiftViewport::duplicatePreset(const QString& path) {
    const QFileInfo f(path);
    if (f.absolutePath() != QFileInfo(presetsFolder()).absoluteFilePath()) {
        last_error_ = QStringLiteral("not a preset path");
        return false;
    }
    const QString base = f.completeBaseName();
    QString copyName = base + QStringLiteral(" copy");
    QString newPath = QDir(presetsFolder()).filePath(copyName + QStringLiteral(".rt"));
    int idx = 2;
    while (QFile::exists(newPath)) {
        newPath = QDir(presetsFolder()).filePath(QStringLiteral("%1 copy %2.rt").arg(base).arg(idx++));
    }
    const bool ok = QFile::copy(path, newPath);
    if (ok) emit presetsChanged();
    return ok;
}

bool RiftViewport::saveProject(const QUrl& url, bool asProject) {
    const QString path = url.isLocalFile() ? url.toLocalFile() : url.toString();
    if (path.isEmpty()) { last_error_ = QStringLiteral("no path"); return false; }

    const QJsonObject root =
        projectJson_(asProject, QFileInfo(path).completeBaseName());

    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        last_error_ = QStringLiteral("cannot write ") + path;
        emit projectChanged();
        return false;
    }
    f.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    // Only a PROJECT save re-points the session at the file it wrote. Saving a
    // preset used to set this too, so the session silently became "the preset",
    // and the next Ctrl+S overwrote the preset in the library instead of the
    // project - which is how edits made after applying a preset ended up
    // rewriting it.
    if (asProject) project_path_ = path;
    last_error_ = QStringLiteral("saved ") + QFileInfo(path).fileName();
    emit projectChanged();
    return true;
}

// The whole session as JSON. Split out of saveProject so undo can snapshot
// through the SAME serializer the file format uses - a second one would drift,
// and undo would quietly stop restoring whatever it forgot.
QJsonObject RiftViewport::projectJson_(bool asProject,
                                       const QString& name) const {
    QJsonObject root;
    root[QStringLiteral("format")]  = QStringLiteral("rift-project");
    root[QStringLiteral("version")] = 5;   // 5 adds "audio_clips" and clip "link"
    root[QStringLiteral("name")]    = name;
    root[QStringLiteral("kind")]    = asProject ? QStringLiteral("project")
                                                : QStringLiteral("preset");
    // A preset is a LOOK. Mode, the audio it happened to be auditioned against,
    // the clips and the markers all belong to the piece, not to the look, and
    // writing them meant applying a preset swapped the user's track and flipped
    // React/Live under them.
    if (asProject) {
        root[QStringLiteral("mode")]   = mode_;
        root[QStringLiteral("aspect")] = project_aspect_;
        // Forward slashes everywhere, so a project saved, reloaded and saved
        // again is byte-identical instead of flip-flopping separators.
        if (!d_->pending_analysis_path.isEmpty())
            root[QStringLiteral("analysis_path")] =
                QDir::fromNativeSeparators(d_->pending_analysis_path);
    }

    QJsonArray grade;
    for (const auto& p : grade_params_) grade.append(paramToJson(p));
    root[QStringLiteral("grade")] = grade;

    // Controller bindings. Worth persisting: re-learning a whole controller
    // after every reload defeats the point of mapping it.
    QJsonArray controls;
    for (auto it = control_map_.cbegin(); it != control_map_.cend(); ++it) {
        QJsonObject c;
        c[QStringLiteral("key")]   = it.key();
        c[QStringLiteral("node")]  = it->node;
        c[QStringLiteral("param")] = it->param;
        controls.append(c);
    }
    if (!controls.isEmpty()) root[QStringLiteral("controls")] = controls;

    // Markers: only worth storing once they have been edited by hand. Detected
    // ones are reproducible from the audio, and freezing them would mean a
    // re-detect with better settings never reaches an existing project. They
    // are positions in a particular track, so a preset carries none.
    if (asProject && markers_edited_ && !markers_.empty()) {
        QJsonArray mk;
        for (double t : markers_) mk.append(t);
        root[QStringLiteral("markers")] = mk;
    }

    // Shared chain. While a clip is selected the rail holds THAT clip's stack
    // (stored on the clip itself) and the shared chain is parked, so read the
    // parked copy in that case. Omitting the key instead meant saving - or
    // taking an undo snapshot - with a clip selected dropped the shared chain
    // from the document entirely, and the read side skips a missing "chain",
    // so undo could not put it back either.
    {
        QJsonArray chain;
        std::lock_guard<std::mutex> lk(d_->params_mu);
        const auto& nodes = (edited_clip_ >= 0 && d_->shared_parked)
                          ? d_->shared_chain : d_->chain;
        for (const auto& n : nodes) {
            QJsonObject node;
            node[QStringLiteral("shader")] = n.effect;
            QJsonArray ps;
            for (const auto& p : n.params) ps.append(paramToJson(p));
            node[QStringLiteral("params")] = ps;
            if (n.blend != rift::Blend_Normal)
                node[QStringLiteral("blend")] = n.blend;
            if (n.mix < 0.999f) node[QStringLiteral("mix")] = double(n.mix);
            chain.append(node);
        }
        root[QStringLiteral("chain")] = chain;
    }

    if (asProject) {
        QJsonArray clips;
        for (const auto& c : clip_specs_) {
            QJsonObject o;
            o[QStringLiteral("path")]    =
                QDir::fromNativeSeparators(QString::fromStdString(c.path));
            o[QStringLiteral("start")]   = c.start;
            o[QStringLiteral("in")]      = c.in;
            o[QStringLiteral("out")]     = c.out;
            o[QStringLiteral("lane")]    = c.lane;
            o[QStringLiteral("blend")]   = c.blend;
            o[QStringLiteral("opacity")] = c.opacity;
            o[QStringLiteral("posX")]    = c.posX;
            o[QStringLiteral("posY")]    = c.posY;
            o[QStringLiteral("scale")]   = c.scale;
            o[QStringLiteral("cropX")]   = c.cropX;
            o[QStringLiteral("cropY")]   = c.cropY;
            o[QStringLiteral("cropW")]   = c.cropW;
            o[QStringLiteral("cropH")]   = c.cropH;
            if (c.link >= 0) o[QStringLiteral("link")] = c.link;
            if (c.kind == rift::ClipSpec::Text) {
                o[QStringLiteral("kind")] = QStringLiteral("text");
                QJsonObject t;
                t[QStringLiteral("text")] = QString::fromStdString(c.text.text);
                if (!c.text.font.empty())
                    t[QStringLiteral("font")] = QString::fromStdString(c.text.font);
                t[QStringLiteral("size")] = c.text.size;
                t[QStringLiteral("x")]    = c.text.x;
                t[QStringLiteral("y")]    = c.text.y;
                t[QStringLiteral("r")]    = double(c.text.r);
                t[QStringLiteral("g")]    = double(c.text.g);
                t[QStringLiteral("b")]    = double(c.text.b);
                if (c.text.bold) t[QStringLiteral("bold")] = true;
                if (c.text.letterSpacing != 0.0)
                    t[QStringLiteral("letterSpacing")] = c.text.letterSpacing;
                if (c.text.wrapWidth != 0.0)
                    t[QStringLiteral("wrapWidth")] = c.text.wrapWidth;
                o[QStringLiteral("textSpec")] = t;
            }
            QJsonArray chain;
            for (const auto& pass : c.chain) {
                QJsonObject node;
                node[QStringLiteral("shader")] =
                    QString::fromStdString(pass.shader);
                QJsonArray ps;
                for (const auto& p : pass.params) ps.append(paramToJson(p));
                node[QStringLiteral("params")] = ps;
                if (pass.blend != rift::Blend_Normal)
                    node[QStringLiteral("blend")] = pass.blend;
                if (pass.mix < 0.999f)
                    node[QStringLiteral("mix")] = double(pass.mix);
                chain.append(node);
            }
            if (!chain.isEmpty()) o[QStringLiteral("chain")] = chain;
            clips.append(o);
        }
        root[QStringLiteral("clips")] = clips;

        QJsonArray audioClips;
        for (const auto& a : audio_clip_specs_) {
            QJsonObject o;
            o[QStringLiteral("path")]  =
                QDir::fromNativeSeparators(QString::fromStdString(a.path));
            o[QStringLiteral("name")]  = QString::fromStdString(a.name);
            o[QStringLiteral("start")] = a.start;
            o[QStringLiteral("in")]    = a.in;
            o[QStringLiteral("out")]   = a.out;
            o[QStringLiteral("lane")]  = a.lane;
            o[QStringLiteral("gain")]  = a.gain;
            if (a.link >= 0) o[QStringLiteral("link")] = a.link;
            audioClips.append(o);
        }
        if (!audioClips.isEmpty()) root[QStringLiteral("audio_clips")] = audioClips;
    }

    QJsonArray visArr;
    for (int i = 0; i < 4; ++i) {
        visArr.append(vis_color_styles_[i]);
    }
    root[QStringLiteral("visualizerStyles")] = visArr;
    root[QStringLiteral("linkAllVisualizers")] = link_all_visualizers_;

    return root;
}

bool RiftViewport::loadProject(const QUrl& url) {
    const QString path = url.isLocalFile() ? url.toLocalFile() : url.toString();
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        last_error_ = QStringLiteral("cannot read ") + path;
        emit projectChanged();
        return false;
    }
    const QJsonObject root = QJsonDocument::fromJson(f.readAll()).object();
    if (root.value(QStringLiteral("format")).toString()
        != QLatin1String("rift-project")) {
        last_error_ = QStringLiteral("not a rift project");
        emit projectChanged();
        return false;
    }
    // Loading a project is itself undoable, and the loaded state becomes the
    // new baseline - otherwise undo would step back into the previous project.
    pushUndo_(QStringLiteral("open project"), QStringLiteral("open"));
    project_path_ = path;
    const bool ok = applyProjectJson_(root);
    clearRedo_();
    return ok;
}

// Restore a session from JSON. Split out of loadProject so undo replays through
// the SAME deserializer the file format uses.
bool RiftViewport::applyProjectJson_(const QJsonObject& root, bool asProject) {
    const int version = root.value(QStringLiteral("version")).toInt(1);

    // Sources. v2 and older name a single media file; v3 uses `clips`.
    // Ignored outright when applying a preset: builds before 0.1.3 wrote the
    // audio path into every preset, so honouring the file would keep swapping
    // the user's track for whatever was loaded when the preset was saved.
    const QString audio = asProject
        ? root.value(QStringLiteral("audio_path")).toString() : QString();
    const QString analysis = asProject
        ? root.value(QStringLiteral("analysis_path")).toString() : QString();

    if (asProject && root.contains(QStringLiteral("aspect")))
        setProjectAspect(root.value(QStringLiteral("aspect")).toInt(0));

    if (root.contains(QStringLiteral("visualizerStyles"))) {
        QJsonArray visArr = root.value(QStringLiteral("visualizerStyles")).toArray();
        for (int i = 0; i < 4 && i < visArr.size(); ++i) {
            vis_color_styles_[i] = visArr[i].toObject();
            bakeAndUploadLut_(i);
            emit visualizerColorStyleChanged(i);
        }
    }
    if (root.contains(QStringLiteral("linkAllVisualizers"))) {
        link_all_visualizers_ = root.value(QStringLiteral("linkAllVisualizers")).toBool();
        emit linkAllVisualizersChanged();
    }

    // Clips are optional: a preset carries none and applies over what is loaded.
    if (asProject && root.contains(QStringLiteral("clips"))) {
        clip_specs_.clear();
        for (const QJsonValue& cv : root.value(QStringLiteral("clips")).toArray()) {
            const QJsonObject o = cv.toObject();
            rift::ClipSpec c;
            c.path    = o.value(QStringLiteral("path")).toString().toStdString();
            c.start   = o.value(QStringLiteral("start")).toDouble(-1.0);
            c.in      = o.value(QStringLiteral("in")).toDouble(0.0);
            c.out     = o.value(QStringLiteral("out")).toDouble(0.0);
            c.lane    = o.value(QStringLiteral("lane")).toInt(0);
            c.blend   = o.value(QStringLiteral("blend")).toInt(0);
            c.opacity = o.value(QStringLiteral("opacity")).toDouble(1.0);
            c.posX    = o.value(QStringLiteral("posX")).toDouble(0.0);
            c.posY    = o.value(QStringLiteral("posY")).toDouble(0.0);
            c.scale   = o.value(QStringLiteral("scale")).toDouble(1.0);
            c.cropX   = o.value(QStringLiteral("cropX")).toDouble(0.0);
            c.cropY   = o.value(QStringLiteral("cropY")).toDouble(0.0);
            c.cropW   = o.value(QStringLiteral("cropW")).toDouble(1.0);
            c.cropH   = o.value(QStringLiteral("cropH")).toDouble(1.0);
            c.link    = o.value(QStringLiteral("link")).toInt(-1);
            if (o.value(QStringLiteral("kind")).toString()
                == QLatin1String("text")) {
                c.kind = rift::ClipSpec::Text;
                const QJsonObject t = o.value(QStringLiteral("textSpec")).toObject();
                c.text.text = t.value(QStringLiteral("text")).toString().toStdString();
                c.text.font = t.value(QStringLiteral("font")).toString().toStdString();
                c.text.size = t.value(QStringLiteral("size")).toDouble(0.18);
                c.text.x    = t.value(QStringLiteral("x")).toDouble(0.5);
                c.text.y    = t.value(QStringLiteral("y")).toDouble(0.5);
                c.text.r    = float(t.value(QStringLiteral("r")).toDouble(1.0));
                c.text.g    = float(t.value(QStringLiteral("g")).toDouble(1.0));
                c.text.b    = float(t.value(QStringLiteral("b")).toDouble(1.0));
                c.text.bold = t.value(QStringLiteral("bold")).toBool(false);
                c.text.letterSpacing =
                    t.value(QStringLiteral("letterSpacing")).toDouble(0.0);
                c.text.wrapWidth =
                    t.value(QStringLiteral("wrapWidth")).toDouble(0.0);
            }
            // Per-clip stacks are restored below, once manifests give ranges.
            clip_specs_.push_back(c);
        }
    } else if (version < 3) {
        const QString media = root.value(QStringLiteral("media_path")).toString();
        if (!media.isEmpty()) {
            clip_specs_.clear();
            rift::ClipSpec mc;
            mc.path = media.toStdString();
            mc.start = 0.0;
            clip_specs_.push_back(mc);
        }
    }

    // Shared chain. v3 stores it flat; v2 keeps effect nodes inside `graph`.
    QJsonArray chainArr = root.value(QStringLiteral("chain")).toArray();
    if (chainArr.isEmpty() && version < 3) {
        for (const QJsonValue& nv :
             root.value(QStringLiteral("graph")).toObject()
                 .value(QStringLiteral("nodes")).toArray()) {
            const QJsonObject n = nv.toObject();
            if (n.value(QStringLiteral("type")).toString() != QLatin1String("effect"))
                continue;
            QJsonObject node;
            node[QStringLiteral("shader")] = n.value(QStringLiteral("shader"));
            chainArr.append(node);          // params re-derived from manifests
        }
    }

    if (!chainArr.isEmpty()) {
        // The restored chain IS the shared one, so come back to the shared view
        // rather than loading it underneath a clip's rail and stranding the
        // parked copy (which the next selectClip(-1) would then put back).
        edited_clip_ = -1;
        {
            std::lock_guard<std::mutex> lk(d_->params_mu);
            d_->shared_chain.clear();
            d_->shared_parked = false;
            d_->chain.clear();
            for (const QJsonValue& nv : chainArr)
                d_->chain.push_back({ nv.toObject().value(QStringLiteral("shader"))
                                        .toString(), {}, {}, 0 });
            selected_ = 0;
            d_->chain_dirty = true;
        }
        // Manifests first (ranges + labels), then saved values over the top.
        for (int i = 0; i < int(d_->chain.size()); ++i) loadManifest_(i);
        {
            std::lock_guard<std::mutex> lk(d_->params_mu);
            for (int i = 0; i < int(d_->chain.size()) && i < chainArr.size(); ++i) {
                const QJsonObject n = chainArr.at(i).toObject();
                const QJsonArray ps = n.value(QStringLiteral("params")).toArray();
                auto& dst = d_->chain[i].params;
                for (int p = 0; p < int(dst.size()) && p < ps.size(); ++p)
                    paramFromJson(ps.at(p).toObject(), dst[p]);
                // Absent in v3 and earlier: defaults are a plain replace.
                d_->chain[i].blend = n.value(QStringLiteral("blend")).toInt(0);
                d_->chain[i].mix   =
                    float(n.value(QStringLiteral("mix")).toDouble(1.0));
            }
        }
    }

    // Grade: manifest for ranges, then saved values.
    loadGradeManifest_();
    const QJsonArray gradeArr = root.value(QStringLiteral("grade")).toArray();
    for (int i = 0; i < int(grade_params_.size()) && i < gradeArr.size(); ++i)
        paramFromJson(gradeArr.at(i).toObject(), grade_params_[i]);
    // Republish the whole row, not just the value: a saved grade can carry an
    // audio binding and keyframes, and the panel needs those to show them.
    publishGrade_();
    refreshGradeKeyState_();

    // Controller bindings (v4+). Absent in older projects, which just means
    // nothing is mapped.
    control_map_.clear();
    for (const QJsonValue& cv : root.value(QStringLiteral("controls")).toArray()) {
        const QJsonObject c = cv.toObject();
        const QString key = c.value(QStringLiteral("key")).toString();
        if (key.isEmpty()) continue;
        control_map_.insert(key, { c.value(QStringLiteral("node")).toInt(),
                                   c.value(QStringLiteral("param")).toInt() });
    }
    emit controlChanged();

    // Not for a preset: which of React/Live you are working in is a property of
    // the session, and having a look flip you into the other mode mid-set is
    // the opposite of useful. Old presets stored it, hence the guard here
    // rather than only at the point of writing.
    if (asProject) setMode(root.value(QStringLiteral("mode")).toInt(0));

    // Markers (v4+). Present only when hand-edited; otherwise detection on the
    // loaded audio fills them in.
    if (root.contains(QStringLiteral("markers"))) {
        markers_.clear();
        for (const QJsonValue& mv : root.value(QStringLiteral("markers")).toArray())
            markers_.push_back(mv.toDouble());
        markers_edited_ = true;
        publishMarkers_();
    }

    // Per-clip stacks need manifest ranges too, so rebuild them here.
    if (root.contains(QStringLiteral("clips"))) {
        const QJsonArray clipsArr = root.value(QStringLiteral("clips")).toArray();
        for (int ci = 0; ci < int(clip_specs_.size()) && ci < clipsArr.size(); ++ci) {
            const QJsonArray nodes =
                clipsArr.at(ci).toObject().value(QStringLiteral("chain")).toArray();
            std::vector<rift::ChainPass> chain;
            for (const QJsonValue& nv : nodes) {
                const QJsonObject n = nv.toObject();
                const QString shader = n.value(QStringLiteral("shader")).toString();
                if (shader == QLatin1String("ascii") && nodes.size() == 1) continue;
                std::vector<rift::Param> ps;
                for (const QJsonValue& pv : n.value(QStringLiteral("params")).toArray()) {
                    rift::Param p{};
                    p.min_v = -1e9f; p.max_v = 1e9f;   // widened; manifest wins on edit
                    p.bind.channel = -1;
                    paramFromJson(pv.toObject(), p);
                    ps.push_back(p);
                }
                chain.emplace_back(shader.toStdString(), std::move(ps),
                                   n.value(QStringLiteral("blend")).toInt(0),
                                   float(n.value(QStringLiteral("mix"))
                                             .toDouble(1.0)));
            }
            clip_specs_[ci].chain = std::move(chain);
        }
    }

    if (asProject) {
        if (root.contains(QStringLiteral("audio_clips"))) {
            audio_clip_specs_.clear();
            for (const QJsonValue& av : root.value(QStringLiteral("audio_clips")).toArray()) {
                const QJsonObject o = av.toObject();
                rift::AudioClipSpec a;
                a.path  = o.value(QStringLiteral("path")).toString().toStdString();
                a.name  = o.value(QStringLiteral("name")).toString().toStdString();
                a.start = o.value(QStringLiteral("start")).toDouble(-1.0);
                a.in    = o.value(QStringLiteral("in")).toDouble(0.0);
                a.out   = o.value(QStringLiteral("out")).toDouble(0.0);
                a.lane  = o.value(QStringLiteral("lane")).toInt(0);
                a.gain  = o.value(QStringLiteral("gain")).toDouble(1.0);
                a.link  = o.value(QStringLiteral("link")).toInt(-1);
                audio_clip_specs_.push_back(a);
            }
            d_->pending_audio_path.clear();
            d_->pending_analysis_path = analysis;
            has_audio_ = !audio_clip_specs_.empty();
            pushAudioClips_();
        } else if (!audio.isEmpty()) {
            loadAudio(QUrl::fromLocalFile(audio),
                      analysis.isEmpty() ? QUrl()
                                         : QUrl::fromLocalFile(analysis));
        }
    }
    if (!clip_specs_.empty()) {
        media_name_ = QFileInfo(QString::fromStdString(clip_specs_.front().path))
                          .fileName();
        has_media_ = true;
    }
    pushClips_();
    publishParams_();
    emit chainChanged();
    emit effectChanged();
    emit sourceChanged();

    last_error_ = QStringLiteral("loaded ")
                + root.value(QStringLiteral("name")).toString();
    emit projectChanged();
    update();
    return true;
}

void RiftViewport::setParam(int index, qreal value) {
    if (index < 0 || index >= params_ui_.size()) return;
    // Tagged per (node, param) so dragging one slider coalesces, but moving to
    // a different slider starts a new step.
    pushUndo_(QStringLiteral("param"),
              QStringLiteral("param:%1:%2").arg(selected_).arg(index));

    QVariantMap m = params_ui_.at(index).toMap();
    m[QStringLiteral("value")] = value;
    params_ui_[index] = m;

    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (selected_ < int(d_->chain.size())) {
            auto& ps = d_->chain[selected_].params;
            if (index < int(ps.size())) {
                ps[index].value = float(value);
                d_->params_dirty = true;
            }
        }
    }
    if (d_->engine && m.value(QStringLiteral("name")).toString() == QStringLiteral("tilt")) {
        d_->engine->setSpectrumSlope(float(value));
    }
    syncChainToClip_();
    update();
}

void RiftViewport::setBinding(int index, int channel, qreal depth) {
    if (index < 0 || index >= params_ui_.size()) return;
    pushUndo_(QStringLiteral("patch"), QStringLiteral("patch:%1:%2").arg(selected_).arg(index));
    if (channel >= RIFT_CH_COUNT) return;
    if (channel < 0) channel = -1;                 // anything negative = static

    QVariantMap m = params_ui_.at(index).toMap();
    m[QStringLiteral("channel")] = channel;
    m[QStringLiteral("depth")]   = depth;
    params_ui_[index] = m;

    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (selected_ < int(d_->chain.size())) {
            auto& ps = d_->chain[selected_].params;
            if (index < int(ps.size())) {
                auto& p = ps[index];
                p.bind.channel = channel;
                p.bind.depth   = float(depth);
                p.env = 0.f;                       // no smear across a re-patch
                d_->params_dirty = true;
            }
        }
    }
    emit paramsChanged();                          // not mid-drag; safe to rebuild
    update();
}

// ── export ────────────────────────────────────────────────────────────────
// A second Engine in offscreen mode: it owns its own QRhi and render thread,
// so the export never touches Qt Quick's device and the live viewport keeps
// running at full rate while frames are encoded.
// Capture everything an export needs, right now. Taken by value so the session
// can keep changing without altering an already-queued render.
RiftViewport::ExportJob RiftViewport::snapshotJob_(const QString& out, int quality,
                                                   int w, int h, int fps, bool noWatermark) const {
    ExportJob j;
    j.out          = out;
    j.audio        = d_->pending_audio_path;
    j.analysis     = d_->pending_analysis_path;
    j.quality      = qBound(0, quality, 3);
    j.width        = w > 0 ? w : 1920;
    j.height       = h > 0 ? h : 1080;
    j.fps          = fps > 0 ? fps : 60;
    j.mark_in      = mark_in_;
    j.mark_out     = mark_out_;
    j.no_watermark = noWatermark;

    // The WHOLE track, not just the first file: clip positions, trims, lanes,
    // blends and per-clip stacks all live here.
    j.clips = clip_specs_;
    j.audio_clips = audio_clip_specs_;
    if (j.clips.empty() && !d_->pending_media_path.isEmpty()) {
        rift::ClipSpec jc;
        jc.path  = d_->pending_media_path.toStdString();
        jc.start = 0.0;
        j.clips.push_back(jc);
    }

    {
        // The WHOLE chain, in order - an export must match what the preview
        // shows, not just the node that happens to be selected.
        std::lock_guard<std::mutex> lk(d_->params_mu);
        j.chain.reserve(d_->chain.size());
        for (const auto& n : d_->chain)
            j.chain.push_back({ n.effect.toStdString(), n.params, n.blend, n.mix });
    }
    j.grade = grade_params_;      // the grade is applied to exported frames too
    return j;
}

// Build a fresh engine for one job and start it. Every job gets its own engine:
// it owns a QRhi and a render thread, and reusing one across jobs would mean
// unpicking all of its queued state between renders.
void RiftViewport::beginJob_(int index) {
    if (index < 0 || index >= int(jobs_.size())) return;
    ExportJob& j = jobs_[index];

    current_job_ = index;
    j.state = QStringLiteral("RUNNING");
    j.percent = 0;

    d_->export_out = j.out;
    d_->export_engine = std::make_unique<rift::Engine>(
        nullptr, shader_dir_.toStdString(), shader_dir_.toStdString());

    if (!j.clips.empty()) d_->export_engine->setClips(j.clips);
    if (!j.audio_clips.empty())
        d_->export_engine->setAudioClips(j.audio_clips, j.analysis.toStdString());
    else if (!j.audio.isEmpty())
        d_->export_engine->loadAudio(j.audio.toStdString(),
                                     j.analysis.toStdString());
    if (!j.chain.empty()) d_->export_engine->setChain(j.chain);
    if (!j.grade.empty()) d_->export_engine->setGrade(j.grade);
    for (int i = 0; i < 4; ++i) bakeAndUploadLut_(i);

    rift_export_spec spec{};
    spec.width   = j.width;
    spec.height  = j.height;
    spec.fps     = j.fps;
    spec.quality = rift_export_quality(j.quality);
    spec.no_watermark = j.no_watermark ? 1 : 0;
    // rift_export_spec holds raw const char*, so the buffers must outlive the
    // call - a temporary from toUtf8() would dangle immediately.
    d_->export_out_utf8 = j.out.toUtf8();
    spec.out_path = d_->export_out_utf8.constData();
    if (!j.audio.isEmpty()) {
        d_->export_audio_utf8 = j.audio.toUtf8();
        spec.audio_path = d_->export_audio_utf8.constData();
    }
    // Text overlays are rasterised by the exporter with its OWN QFontDatabase,
    // so the families the shell registered at startup are not visible to it.
    // Without this a text layer that looks right in the viewport comes out of
    // an export in a system fallback face.
    // Export only the marked range when one is set - the range this job was
    // QUEUED with, not whatever is marked now.
    spec.mark_in  = j.mark_in;
    spec.mark_out = j.mark_out;

    d_->export_font_utf8 =
        rift::assetDir(QStringLiteral("fonts"),
                       QStringLiteral(RIFT_FONT_DIR)).toUtf8();
    if (!d_->export_font_utf8.isEmpty())
        spec.font_dir = d_->export_font_utf8.constData();

    exporting_ = true; export_pct_ = 0;
    export_status_ = QStringLiteral("starting");
    emit exportChanged();
    publishQueue_();

    // Fires on the export engine's render thread - hop to the GUI thread.
    d_->export_engine->exportStart(spec, [](int32_t pct, int32_t done, void* user) {
        auto* self = static_cast<RiftViewport*>(user);
        QMetaObject::invokeMethod(self, "onExportProgress", Qt::QueuedConnection,
                                  Q_ARG(int, int(pct)), Q_ARG(bool, done != 0));
    }, this);
}

void RiftViewport::startExport(const QUrl& outUrl, int quality,
                               int width, int height, int fps, bool noWatermark) {
    if (exporting_) return;
    const QString out = outUrl.isLocalFile() ? outUrl.toLocalFile() : outUrl.toString();
    if (out.isEmpty()) return;

    // A single export is a one-job queue. Same path, so there is only one way
    // an export can be set up and it cannot drift between the two.
    jobs_.push_back(snapshotJob_(out, quality, width, height, fps, noWatermark));
    queue_running_ = false;             // do not roll on into other pending jobs
    beginJob_(int(jobs_.size()) - 1);
}

void RiftViewport::cancelExport() {
    if (d_->export_engine) d_->export_engine->exportCancel();
    // A cancelled render still finishes its container and reports success, so
    // remember the intent here or the job would be filed as Done.
    cancel_requested_ = true;
    export_status_ = QStringLiteral("cancelling");
    emit exportChanged();
}

void RiftViewport::onExportProgress(int percent, bool done) {
    export_pct_ = percent;
    if (current_job_ >= 0 && current_job_ < int(jobs_.size()))
        jobs_[current_job_].percent = percent < 0 ? 0 : percent;

    if (done) {
        exporting_ = false;
        export_status_ = percent < 0 ? QStringLiteral("FAILED")
                                     : QStringLiteral("done: ") + d_->export_out;
        // Destroying the engine joins its render thread; safe here on the GUI
        // thread because the callback has already returned.
        d_->export_engine.reset();

        if (current_job_ >= 0 && current_job_ < int(jobs_.size())) {
            jobs_[current_job_].state =
                cancel_requested_ ? QStringLiteral("CANCELLED")
                                  : (percent < 0 ? QStringLiteral("FAILED")
                                                 : QStringLiteral("DONE"));
            jobs_[current_job_].percent = percent < 0 ? 0 : 100;
        }
        current_job_ = -1;
        cancel_requested_ = false;
        publishQueue_();
        emit exportChanged();
        // A failed job does NOT stop the queue: one bad output path should not
        // throw away an overnight batch.
        if (queue_running_) runNextJob_();
        return;
    }
    export_status_ = QStringLiteral("exporting %1%").arg(percent);
    publishQueue_();
    emit exportChanged();
}

// ── undo / redo ────────────────────────────────────────────────────────────
void RiftViewport::pushUndo_(const QString& label, const QString& tag) {
    if (applying_history_) return;      // a restore is not itself an edit

    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    // Coalesce: a slider drag fires setParam continuously, and one undo step
    // per pixel would make undo useless. The FIRST pre-state of a run is the
    // correct restore point, so a repeat of the same tag pushes nothing.
    if (!undo_.empty() && undo_.back().tag == tag
        && now - undo_.back().at < kCoalesceMs) {
        undo_.back().at = now;
        return;
    }

    Snapshot s;
    s.state = projectJson_(true, QStringLiteral("undo"));
    s.label = label;
    s.tag   = tag;
    s.at    = now;
    undo_.push_back(std::move(s));
    if (undo_.size() > kUndoDepth) undo_.erase(undo_.begin());
    clearRedo_();                       // a new edit invalidates the redo path
    emit historyChanged();
}

void RiftViewport::clearRedo_() {
    if (redo_.empty()) return;
    redo_.clear();
    emit historyChanged();
}

void RiftViewport::applySnapshot_(const Snapshot& s) {
    applying_history_ = true;
    applyProjectJson_(s.state);
    applying_history_ = false;
}

void RiftViewport::undo() {
    if (undo_.empty()) return;

    // Capture where we are now so redo can come back to it. Uses the popped
    // step's own label, so "undo add node" / "redo add node" read the same.
    Snapshot cur;
    cur.state = projectJson_(true, QStringLiteral("redo"));
    cur.label = undo_.back().label;
    cur.tag   = undo_.back().tag;
    redo_.push_back(std::move(cur));

    const Snapshot s = undo_.back();
    undo_.pop_back();
    applySnapshot_(s);
    last_error_ = QStringLiteral("undo ") + s.label;
    emit historyChanged();
    emit projectChanged();
}

void RiftViewport::redo() {
    if (redo_.empty()) return;

    Snapshot cur;
    cur.state = projectJson_(true, QStringLiteral("undo"));
    cur.label = redo_.back().label;
    cur.tag   = redo_.back().tag;
    cur.at    = QDateTime::currentMSecsSinceEpoch();
    undo_.push_back(std::move(cur));

    const Snapshot s = redo_.back();
    redo_.pop_back();
    applySnapshot_(s);
    last_error_ = QStringLiteral("redo ") + s.label;
    emit historyChanged();
    emit projectChanged();
}

// ── render queue ──────────────────────────────────────────────────────────
void RiftViewport::publishQueue_() {
    queue_ui_.clear();
    queue_ui_.reserve(int(jobs_.size()));
    for (int i = 0; i < int(jobs_.size()); ++i) {
        const auto& j = jobs_[i];
        QVariantMap m;
        m[QStringLiteral("index")]   = i;
        m[QStringLiteral("out")]     = j.out;
        m[QStringLiteral("name")]    = QFileInfo(j.out).fileName();
        m[QStringLiteral("quality")] = j.quality;
        m[QStringLiteral("width")]   = j.width;
        m[QStringLiteral("height")]  = j.height;
        m[QStringLiteral("fps")]     = j.fps;
        m[QStringLiteral("clips")]   = int(j.clips.size());
        m[QStringLiteral("state")]     = j.state;
        m[QStringLiteral("stateName")] = j.state;
        m[QStringLiteral("percent")] = j.percent;
        queue_ui_.append(m);
    }
    emit queueChanged();
}

void RiftViewport::enqueueExport(const QUrl& outUrl, int quality,
                                 int width, int height, int fps) {
    const QString out = outUrl.isLocalFile() ? outUrl.toLocalFile()
                                             : outUrl.toString();
    if (out.isEmpty()) return;
    jobs_.push_back(snapshotJob_(out, quality, width, height, fps));
    publishQueue_();
}

void RiftViewport::startQueue() {
    if (queue_running_) return;
    queue_running_ = true;
    emit queueChanged();
    if (!exporting_) runNextJob_();     // otherwise the running job picks it up
}

void RiftViewport::stopQueue() {
    queue_running_ = false;
    // Deliberately does NOT kill the running job: "stop after this one" is what
    // you want mid-batch. cancelExport() is there to abandon the current render.
    publishQueue_();
}

void RiftViewport::runNextJob_() {
    for (int i = 0; i < int(jobs_.size()); ++i) {
        if (jobs_[i].state == QLatin1String("PENDING")) { beginJob_(i); return; }
    }
    queue_running_ = false;             // nothing left
    publishQueue_();
}

void RiftViewport::removeJob(int index) {
    if (index < 0 || index >= int(jobs_.size())) return;
    if (jobs_[index].state == QLatin1String("RUNNING")) return;  // cancel instead
    jobs_.erase(jobs_.begin() + index);
    if (current_job_ > index) --current_job_;
    publishQueue_();
}

void RiftViewport::clearQueue() {
    for (int i = int(jobs_.size()) - 1; i >= 0; --i)
        if (jobs_[i].state != QLatin1String("RUNNING")) {
            jobs_.erase(jobs_.begin() + i);
            if (current_job_ > i) --current_job_;
        }
    publishQueue_();
}

// Batch spec: one job per line, "OUT|QUALITY|WIDTHxHEIGHT|FPS". Everything
// after OUT is optional. Blank lines and '#' comments ignored.
//
// Every job snapshots the session as it is NOW, so a batch file is a list of
// output variants of the current project rather than a list of projects.
bool RiftViewport::loadQueue(const QUrl& url) {
    const QString path = url.isLocalFile() ? url.toLocalFile() : url.toString();
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        last_error_ = QStringLiteral("cannot read ") + path;
        return false;
    }
    QTextStream s(&f);
    int added = 0;
    while (!s.atEnd()) {
        const QString line = s.readLine().trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#'))) continue;

        const QStringList f2 = line.split(QLatin1Char('|'));
        const QString out = f2.value(0).trimmed();
        if (out.isEmpty()) continue;

        int q = f2.size() > 1 ? f2.at(1).trimmed().toInt() : 0;
        int w = 1920, h = 1080;
        if (f2.size() > 2) {
            const QStringList wh = f2.at(2).trimmed().split(QLatin1Char('x'));
            if (wh.size() == 2) { w = wh.at(0).toInt(); h = wh.at(1).toInt(); }
        }
        const int fps = f2.size() > 3 ? f2.at(3).trimmed().toInt() : 60;

        jobs_.push_back(snapshotJob_(out, q, w, h, fps));
        ++added;
    }
    publishQueue_();
    last_error_ = QStringLiteral("queued %1 job(s)").arg(added);
    return added > 0;
}

void RiftViewport::addKey(int paramIndex) {
    pushUndo_(QStringLiteral("add key"), QStringLiteral("addKey:%1").arg(paramIndex));
    // Land the key on the beat the playhead is sitting near, so a key set by
    // eye while playing is exactly on the hit rather than a few ms off it.
    const double t = snapTime(playhead_);
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        int targetNode = selected_;
        if (targetNode < 0 || targetNode >= int(d_->chain.size())) {
            if (!d_->chain.empty()) targetNode = 0;
            else return;
        }
        auto& ps = d_->chain[targetNode].params;
        if (paramIndex < 0 || paramIndex >= int(ps.size())) return;
        auto& keys = ps[paramIndex].keys;

        // Snapped time for PLACEMENT, but the existing-key test accepts either,
        // so re-pressing Set on a key that is not on a beat updates it instead
        // of dropping a second one next to it.
        const int at = keyAtPlayhead_(keys);
        if (at >= 0) {
            keys[at].value = ps[paramIndex].value;   // re-key in place
        } else {
            rift::Keyframe k;
            k.time  = t;
            k.value = ps[paramIndex].value;
            keys.push_back(k);
            std::sort(keys.begin(), keys.end(),
                      [](const rift::Keyframe& a, const rift::Keyframe& b) {
                          return a.time < b.time;
                      });
        }
        d_->params_dirty = true;
    }
    syncChainToClip_();
    publishParams_();
    update();
}

// Keys of the selected node (or all nodes in chain if none selected), flattened so timeline can draw them.
QVariantList RiftViewport::keyframes() const {
    QVariantList out;
    std::lock_guard<std::mutex> lk(d_->params_mu);
    if (d_->chain.empty()) return out;

    const int start = (selected_ >= 0 && selected_ < int(d_->chain.size())) ? selected_ : 0;
    const int end = (selected_ >= 0 && selected_ < int(d_->chain.size())) ? selected_ + 1 : int(d_->chain.size());

    for (int n = start; n < end; ++n) {
        const auto& node = d_->chain[n];
        for (int i = 0; i < int(node.params.size()); ++i) {
            QString label = QStringLiteral("%1 P%2").arg(node.effect).arg(i);
            if (i < node.ui.size()) {
                const QVariantMap m = node.ui.at(i).toMap();
                const QString l = m.value(QStringLiteral("label")).toString();
                if (!l.isEmpty()) label = l;
            }
            for (const auto& k : node.params[i].keys) {
                QVariantMap e;
                e[QStringLiteral("node")]        = n;
                e[QStringLiteral("param")]       = i;
                e[QStringLiteral("paramLabel")]  = label;
                e[QStringLiteral("time")]        = k.time;
                e[QStringLiteral("value")]       = k.value;
                e[QStringLiteral("interp")]      = k.interp;
                out.append(e);
            }
        }
    }
    return out;
}

void RiftViewport::moveKey(int paramIndex, qreal fromTime, qreal toTime) {
    pushUndo_(QStringLiteral("move key"), QStringLiteral("moveKey:%1").arg(paramIndex));
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (selected_ >= int(d_->chain.size())) return;
        auto& ps = d_->chain[selected_].params;
        if (paramIndex < 0 || paramIndex >= int(ps.size())) return;
        auto& keys = ps[paramIndex].keys;

        const int at = nearestKey(keys, double(fromTime));
        if (at < 0) return;
        keys[at].time = std::max(0.0, double(toTime));
        std::sort(keys.begin(), keys.end(),
                  [](const rift::Keyframe& a, const rift::Keyframe& b) {
                      return a.time < b.time;
                  });
        d_->params_dirty = true;
    }
    syncChainToClip_();
    publishParams_();
    update();
}

void RiftViewport::addKeyAt(int paramIndex, qreal time, qreal value, int interp) {
    pushUndo_(QStringLiteral("add key"), QStringLiteral("addKeyAt:%1").arg(paramIndex));
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (selected_ >= int(d_->chain.size())) return;
        auto& ps = d_->chain[selected_].params;
        if (paramIndex < 0 || paramIndex >= int(ps.size())) return;
        auto& keys = ps[paramIndex].keys;

        rift::Keyframe k;
        k.time   = double(time);
        k.value  = float(value);
        k.interp = qBound(0, interp, 2);

        const int at = nearestKey(keys, k.time);
        if (at >= 0) keys[at] = k;
        else {
            keys.push_back(k);
            std::sort(keys.begin(), keys.end(),
                      [](const rift::Keyframe& a, const rift::Keyframe& b) {
                          return a.time < b.time;
                      });
        }
        d_->params_dirty = true;
    }
    syncChainToClip_();
    publishParams_();
    update();
}

void RiftViewport::removeKeyAt(int paramIndex) {
    pushUndo_(QStringLiteral("remove key"), QStringLiteral("removeKey:%1").arg(paramIndex));
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (selected_ >= int(d_->chain.size())) return;
        auto& ps = d_->chain[selected_].params;
        if (paramIndex < 0 || paramIndex >= int(ps.size())) return;
        auto& keys = ps[paramIndex].keys;
        const int at = keyAtPlayhead_(keys);
        if (at < 0) return;
        keys.erase(keys.begin() + at);
        d_->params_dirty = true;
    }
    syncChainToClip_();
    publishParams_();
    update();
}

void RiftViewport::clearKeys(int paramIndex) {
    pushUndo_(QStringLiteral("clear keys"), QStringLiteral("clearKeys:%1").arg(paramIndex));
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (selected_ >= int(d_->chain.size())) return;
        auto& ps = d_->chain[selected_].params;
        if (paramIndex < 0 || paramIndex >= int(ps.size())) return;
        ps[paramIndex].keys.clear();
        d_->params_dirty = true;
    }
    syncChainToClip_();
    publishParams_();
    update();
}

void RiftViewport::cycleKeyInterp(int paramIndex) {
    pushUndo_(QStringLiteral("key interp"), QStringLiteral("keyInterp:%1").arg(paramIndex));
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (selected_ >= int(d_->chain.size())) return;
        auto& ps = d_->chain[selected_].params;
        if (paramIndex < 0 || paramIndex >= int(ps.size())) return;
        auto& keys = ps[paramIndex].keys;
        const int at = keyAtPlayhead_(keys);
        if (at < 0) return;
        keys[at].interp = (keys[at].interp + 1) % 3;   // linear -> ease -> step
        d_->params_dirty = true;
    }
    syncChainToClip_();
    publishParams_();
    update();
}

void RiftViewport::resetParams() {
    pushUndo_(QStringLiteral("reset params"), QStringLiteral("resetParams"));
    for (int i = 0; i < params_ui_.size(); ++i) {
        QVariantMap m = params_ui_.at(i).toMap();
        m[QStringLiteral("value")] = m.value(QStringLiteral("default"));
        params_ui_[i] = m;
    }
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        if (selected_ < int(d_->chain.size())) {
            auto& ps = d_->chain[selected_].params;
            for (int i = 0; i < int(ps.size()) && i < params_ui_.size(); ++i)
                ps[i].value = float(params_ui_.at(i).toMap()
                                    .value(QStringLiteral("default")).toDouble());
            d_->chain[selected_].ui = params_ui_;
        }
        d_->params_dirty = true;
    }
    emit paramsChanged();
    update();
}

void RiftViewport::initVisualizerStyles_() {
    // 0: Oscilloscope
    {
        QJsonObject o;
        o[QStringLiteral("mode")] = QStringLiteral("gradient");
        o[QStringLiteral("solid")] = QStringLiteral("#00ffffff");
        QJsonArray stops;
        QJsonObject s0; s0[QStringLiteral("position")] = 0.0; s0[QStringLiteral("color")] = QStringLiteral("#00ffffff");
        QJsonObject s1; s1[QStringLiteral("position")] = 1.0; s1[QStringLiteral("color")] = QStringLiteral("#ffffffff");
        stops.append(s0); stops.append(s1);
        o[QStringLiteral("stops")] = stops;
        o[QStringLiteral("mapping")] = QStringLiteral("horizontal");
        o[QStringLiteral("glow_color")] = QStringLiteral("match");
        vis_color_styles_[0] = o;
    }
    // 1: Spectrum Analyzer
    {
        QJsonObject o;
        o[QStringLiteral("mode")] = QStringLiteral("gradient");
        o[QStringLiteral("solid")] = QStringLiteral("#ffff8800");
        QJsonArray stops;
        QJsonObject s0; s0[QStringLiteral("position")] = 0.0; s0[QStringLiteral("color")] = QStringLiteral("#ff1a0066");
        QJsonObject s1; s1[QStringLiteral("position")] = 0.4; s1[QStringLiteral("color")] = QStringLiteral("#ffff2266");
        QJsonObject s2; s2[QStringLiteral("position")] = 0.8; s2[QStringLiteral("color")] = QStringLiteral("#ffffaa00");
        QJsonObject s3; s3[QStringLiteral("position")] = 1.0; s3[QStringLiteral("color")] = QStringLiteral("#ffffffcc");
        stops.append(s0); stops.append(s1); stops.append(s2); stops.append(s3);
        o[QStringLiteral("stops")] = stops;
        o[QStringLiteral("mapping")] = QStringLiteral("frequency");
        o[QStringLiteral("glow_color")] = QStringLiteral("match");
        vis_color_styles_[1] = o;
    }
    // 2: Spectrogram
    {
        QJsonObject o;
        o[QStringLiteral("mode")] = QStringLiteral("gradient");
        o[QStringLiteral("solid")] = QStringLiteral("#ffffffff");
        QJsonArray stops;
        QJsonObject s0; s0[QStringLiteral("position")] = 0.0; s0[QStringLiteral("color")] = QStringLiteral("#ff000000");
        QJsonObject s1; s1[QStringLiteral("position")] = 0.25; s1[QStringLiteral("color")] = QStringLiteral("#ff660066");
        QJsonObject s2; s2[QStringLiteral("position")] = 0.5; s2[QStringLiteral("color")] = QStringLiteral("#ffff2200");
        QJsonObject s3; s3[QStringLiteral("position")] = 0.75; s3[QStringLiteral("color")] = QStringLiteral("#ffffcc00");
        QJsonObject s4; s4[QStringLiteral("position")] = 1.0; s4[QStringLiteral("color")] = QStringLiteral("#ffffffff");
        stops.append(s0); stops.append(s1); stops.append(s2); stops.append(s3); stops.append(s4);
        o[QStringLiteral("stops")] = stops;
        o[QStringLiteral("mapping")] = QStringLiteral("db");
        o[QStringLiteral("glow_color")] = QStringLiteral("match");
        vis_color_styles_[2] = o;
    }
    // 3: Lissajous Vectorscope
    {
        QJsonObject o;
        o[QStringLiteral("mode")] = QStringLiteral("gradient");
        o[QStringLiteral("solid")] = QStringLiteral("#ff00ff66");
        QJsonArray stops;
        QJsonObject s0; s0[QStringLiteral("position")] = 0.0; s0[QStringLiteral("color")] = QStringLiteral("#ff003311");
        QJsonObject s1; s1[QStringLiteral("position")] = 0.6; s1[QStringLiteral("color")] = QStringLiteral("#ff00ff66");
        QJsonObject s2; s2[QStringLiteral("position")] = 1.0; s2[QStringLiteral("color")] = QStringLiteral("#ffffffaa");
        stops.append(s0); stops.append(s1); stops.append(s2);
        o[QStringLiteral("stops")] = stops;
        o[QStringLiteral("mapping")] = QStringLiteral("distance");
        o[QStringLiteral("glow_color")] = QStringLiteral("match");
        vis_color_styles_[3] = o;
    }
}

void RiftViewport::bakeAndUploadLut_(int visIndex) {
    if (visIndex < 0 || visIndex >= 4) return;
    const QJsonObject& style = vis_color_styles_[visIndex];
    uint32_t lineLut[256];
    uint32_t glowLut[256];

    QString mode = style.value(QStringLiteral("mode")).toString(QStringLiteral("gradient"));
    if (mode == QStringLiteral("solid")) {
        QColor c(style.value(QStringLiteral("solid")).toString(QStringLiteral("#00ffffff")));
        uint32_t val = (uint32_t(c.alpha()) << 24) | (uint32_t(c.blue()) << 16) |
                       (uint32_t(c.green()) << 8) | uint32_t(c.red());
        for (int i = 0; i < 256; ++i) lineLut[i] = val;
    } else {
        struct Stop { float pos; QColor col; };
        std::vector<Stop> stops;
        QJsonArray arr = style.value(QStringLiteral("stops")).toArray();
        for (auto v : arr) {
            QJsonObject o = v.toObject();
            stops.push_back({ float(o.value(QStringLiteral("position")).toDouble()),
                             QColor(o.value(QStringLiteral("color")).toString()) });
        }
        if (stops.empty()) {
            stops.push_back({ 0.0f, QColor(Qt::white) });
            stops.push_back({ 1.0f, QColor(Qt::white) });
        } else if (stops.size() == 1) {
            stops.push_back({ 1.0f, stops[0].col });
        }
        std::sort(stops.begin(), stops.end(), [](const Stop& a, const Stop& b){ return a.pos < b.pos; });

        for (int i = 0; i < 256; ++i) {
            float t = float(i) / 255.0f;
            QColor col;
            if (t <= stops.front().pos) {
                col = stops.front().col;
            } else if (t >= stops.back().pos) {
                col = stops.back().col;
            } else {
                for (size_t s = 0; s + 1 < stops.size(); ++s) {
                    if (t >= stops[s].pos && t <= stops[s + 1].pos) {
                        float span = std::max(stops[s + 1].pos - stops[s].pos, 1e-5f);
                        float factor = (t - stops[s].pos) / span;
                        int r = int(stops[s].col.red() + factor * (stops[s + 1].col.red() - stops[s].col.red()) + 0.5f);
                        int g = int(stops[s].col.green() + factor * (stops[s + 1].col.green() - stops[s].col.green()) + 0.5f);
                        int b = int(stops[s].col.blue() + factor * (stops[s + 1].col.blue() - stops[s].col.blue()) + 0.5f);
                        int a = int(stops[s].col.alpha() + factor * (stops[s + 1].col.alpha() - stops[s].col.alpha()) + 0.5f);
                        col = QColor(std::clamp(r, 0, 255), std::clamp(g, 0, 255),
                                     std::clamp(b, 0, 255), std::clamp(a, 0, 255));
                        break;
                    }
                }
            }
            lineLut[i] = (uint32_t(col.alpha()) << 24) | (uint32_t(col.blue()) << 16) |
                         (uint32_t(col.green()) << 8) | uint32_t(col.red());
        }
    }

    QString glowColStr = style.value(QStringLiteral("glow_color")).toString(QStringLiteral("match"));
    const uint32_t* glowPtr = nullptr;
    if (glowColStr != QStringLiteral("match")) {
        QColor gc(glowColStr);
        uint32_t gval = (uint32_t(gc.alpha()) << 24) | (uint32_t(gc.blue()) << 16) |
                        (uint32_t(gc.green()) << 8) | uint32_t(gc.red());
        for (int i = 0; i < 256; ++i) glowLut[i] = gval;
        glowPtr = glowLut;
    }

    if (d_->engine && d_->engine->rhiContext()) {
        d_->engine->rhiContext()->uploadLut(visIndex, lineLut, glowPtr);
    }
    if (d_->export_engine && d_->export_engine->rhiContext()) {
        d_->export_engine->rhiContext()->uploadLut(visIndex, lineLut, glowPtr);
    }
}

QJsonObject RiftViewport::visualizerColorStyle(int visIndex) const {
    if (visIndex < 0 || visIndex >= 4) return {};
    return vis_color_styles_[visIndex];
}

void RiftViewport::setVisualizerColorStyle(int visIndex, const QJsonObject& style) {
    if (visIndex < 0 || visIndex >= 4) return;
    if (link_all_visualizers_) {
        for (int i = 0; i < 4; ++i) {
            QJsonObject s = style;
            s[QStringLiteral("mapping")] = vis_color_styles_[i].value(QStringLiteral("mapping"));
            vis_color_styles_[i] = s;
            bakeAndUploadLut_(i);
            emit visualizerColorStyleChanged(i);
        }
    } else {
        vis_color_styles_[visIndex] = style;
        bakeAndUploadLut_(visIndex);
        emit visualizerColorStyleChanged(visIndex);
    }

    int currentVis = 0;
    for (int i = 0; i < params_ui_.size(); ++i) {
        QVariantMap m = params_ui_.at(i).toMap();
        if (m.value(QStringLiteral("name")).toString() == QStringLiteral("mode")) {
            currentVis = int(std::floor(m.value(QStringLiteral("value")).toDouble() + 0.5));
            break;
        }
    }
    if (visIndex == currentVis) {
        QString mapStr = style.value(QStringLiteral("mapping")).toString();
        float mapVal = 0.0f;
        if (mapStr == QStringLiteral("amplitude") || mapStr == QStringLiteral("level") || mapStr == QStringLiteral("age")) {
            mapVal = 1.0f;
        } else if (mapStr == QStringLiteral("angle")) {
            mapVal = 2.0f;
        }
        for (int i = 0; i < params_ui_.size(); ++i) {
            QVariantMap m = params_ui_.at(i).toMap();
            if (m.value(QStringLiteral("name")).toString() == QStringLiteral("mapping")) {
                setParam(i, mapVal);
                break;
            }
        }
    }
    update();
}

void RiftViewport::setLinkAllVisualizers(bool link) {
    if (link_all_visualizers_ == link) return;
    link_all_visualizers_ = link;
    emit linkAllVisualizersChanged();
    if (link) {
        setVisualizerColorStyle(0, vis_color_styles_[0]);
    }
}

bool RiftViewport::saveVisualizerPreset(int visIndex, const QUrl& url) {
    if (visIndex < 0 || visIndex >= 4) return false;
    const QString path = url.isLocalFile() ? url.toLocalFile() : url.toString();
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) return false;
    QJsonObject obj = vis_color_styles_[visIndex];
    f.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    return true;
}

bool RiftViewport::loadVisualizerPreset(int visIndex, const QUrl& url) {
    if (visIndex < 0 || visIndex >= 4) return false;
    const QString path = url.isLocalFile() ? url.toLocalFile() : url.toString();
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) return false;
    QJsonObject obj = QJsonDocument::fromJson(f.readAll()).object();
    if (obj.isEmpty()) return false;
    setVisualizerColorStyle(visIndex, obj);
    return true;
}

void RiftViewport::itemChange(ItemChange change, const ItemChangeData& data) {
    if (change == ItemSceneChange && data.window) {
        // beforeFrameBegin is the ONLY hook where no QRhi frame is open yet -
        // it precedes beforeSynchronizing and beforeRendering, both of which
        // run inside Quick's frame and make beginOffscreenFrame() illegal.
        // Qt documents it for exactly this: starting an offscreen frame.
        connect(data.window, &QQuickWindow::beforeFrameBegin,
                this, &RiftViewport::onBeforeRendering, Qt::DirectConnection);
        connect(data.window, &QQuickWindow::sceneGraphInvalidated,
                this, &RiftViewport::onSceneGraphInvalidated, Qt::DirectConnection);
        data.window->setColor(Qt::black);
    }
    QQuickItem::itemChange(change, data);
}

void RiftViewport::geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) {
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size()) {
        emit framedRectChanged();
    }
}

QRectF RiftViewport::framedRect() const {
    const qreal W = width();
    const qreal H = height();
    if (W <= 0.0 || H <= 0.0) return QRectF();
    double ar = 16.0 / 9.0;
    switch (project_aspect_) {
        case 0: ar = 16.0 / 9.0; break;
        case 1: ar = 1.0; break;
        case 2: ar = 4.0 / 3.0; break;
        case 3: ar = 9.0 / 16.0; break;
        case 4: ar = 21.0 / 9.0; break;
        default: ar = 16.0 / 9.0; break;
    }
    qreal targetW = W;
    qreal targetH = W / ar;
    if (targetH > H) {
        targetH = H;
        targetW = H * ar;
    }
    qreal targetX = (W - targetW) * 0.5;
    qreal targetY = (H - targetH) * 0.5;
    return QRectF(targetX, targetY, targetW, targetH);
}

void RiftViewport::setProjectAspect(int a) {
    if (project_aspect_ == a) return;
    project_aspect_ = a;
    if (d_) {
        d_->sg_scene = 0;
        d_->size = QSize();
    }
    emit projectChanged();
    emit framedRectChanged();
    update();
}

void RiftViewport::onSceneGraphInvalidated() {
    d_->engine.reset();             // must die on the thread that made it
    d_->sg_scene = 0;
    d_->scene = 0;
    d_->chain_dirty = true;        // pipelines died with the scene graph
}

// ── transport (GUI thread) ────────────────────────────────────────────────
// Engine is created lazily on the render thread, so these no-op until the
// first frame has run. QML re-issues them via the bound properties.
// Replaces the track with a single clip - "open this file" rather than "add".
void RiftViewport::loadMedia(const QUrl& url) {
    const QString path = url.isLocalFile() ? url.toLocalFile() : url.toString();
    clip_specs_.clear();
    rift::ClipSpec lc;
    lc.path = path.toStdString();
    lc.start = 0.0;
    clip_specs_.push_back(lc);
    d_->pending_media_path = path;         // request may precede the Engine
    media_name_ = QFileInfo(path).fileName();
    has_media_ = true;
    pushClips_();
    emit sourceChanged();
    update();
}

void RiftViewport::addClip(const QUrl& url, int lane) {
    const QString path = url.isLocalFile() ? url.toLocalFile() : url.toString();
    // Decoding is FFmpeg, and an LGPL build has no SVG decoder. Loading one
    // used to succeed and then render the placeholder checkerboard, which
    // looks like the effects are broken rather than the file being unreadable.
    if (path.endsWith(QLatin1String(".svg"), Qt::CaseInsensitive)) {
        last_error_ = QStringLiteral("SVG cannot be decoded - export it as PNG");
        emit projectChanged();
        return;
    }
    pushUndo_(QStringLiteral("add clip"), QStringLiteral("addClip"));
    // start < 0 = "append after the previous clip IN THIS LANE". The UI cannot
    // compute this itself: a clip's length is unknown until its source opens,
    // so letting the timeline resolve it is what stops clips stacking at 0.
    rift::ClipSpec ac;
    ac.path  = path.toStdString();
    ac.start = -1.0;
    if (lane < 0) {
        // Lowest free lane. Appending into an occupied lane is a cut, which is
        // what the razor is for; a newly imported source almost always wants
        // to sit over what is already there.
        std::vector<bool> used;
        for (const auto& c : clip_specs_) {
            if (c.lane >= int(used.size())) used.resize(c.lane + 1, false);
            used[c.lane] = true;
        }
        int l = 0;
        while (l < int(used.size()) && used[l]) ++l;
        ac.lane = l;
    } else {
        ac.lane = lane;
    }
    clip_specs_.push_back(ac);
    if (media_name_.isEmpty()) media_name_ = QFileInfo(path).fileName();
    has_media_ = true;
    pushClips_();
    emit sourceChanged();
    update();
}

void RiftViewport::removeClip(int index) {
    if (index < 0 || index >= int(clip_specs_.size())) return;
    pushUndo_(QStringLiteral("remove clip"), QStringLiteral("removeClip"));
    // edited_clip_ is an index into this vector. Erasing shifts everything
    // above it down, and syncChainToClip_ would then write the rail's chain
    // into whichever clip slid into the slot - silently replacing an unrelated
    // clip's effect stack. Deleting the clip being edited goes back to the
    // shared view first, which also un-parks the shared chain.
    if (edited_clip_ == index) selectClip(-1);
    else if (edited_clip_ > index) --edited_clip_;
    clip_specs_.erase(clip_specs_.begin() + index);
    pushClips_();
    update();
}

void RiftViewport::setClipLane(int index, int lane) {
    if (index < 0 || index >= int(clip_specs_.size())) return;
    pushUndo_(QStringLiteral("clip lane"), QStringLiteral("clipLane:%1").arg(index));
    clip_specs_[index].lane = std::max(0, lane);
    // Pin the current position, otherwise a clip that was auto-appended would
    // jump to the end of its new lane the moment it moves.
    if (clip_specs_[index].start < 0.0 && d_->engine)
        clip_specs_[index].start = d_->engine->clipStart(index);
    pushClips_();
    update();
}

void RiftViewport::setClipBlend(int index, int blend, qreal opacity) {
    if (index < 0 || index >= int(clip_specs_.size())) return;
    pushUndo_(QStringLiteral("clip blend"), QStringLiteral("clipBlend:%1").arg(index));
    clip_specs_[index].blend   = qBound(0, blend, int(rift::Blend_Count) - 1);
    clip_specs_[index].opacity = qBound(0.0, double(opacity), 1.0);
    pushClips_();
    update();
}

void RiftViewport::setClipTransform(int index, qreal x, qreal y, qreal scale) {
    if (index < 0 || index >= int(clip_specs_.size())) return;
    pushUndo_(QStringLiteral("clip transform"), QStringLiteral("clipXf:%1").arg(index));
    clip_specs_[index].posX  = qBound(-2.0, double(x), 2.0);
    clip_specs_[index].posY  = qBound(-2.0, double(y), 2.0);
    clip_specs_[index].scale = qBound(0.05, double(scale), 4.0);
    pushClips_();
    update();
}

// The rectangle of the frame this clip paints. Two clips cropped to opposite
// halves is split screen; one clip cropped small over another is a window into
// it. Zero width or height would make the clip invisible with no way back from
// the UI, so both are floored.
void RiftViewport::setClipCrop(int index, qreal x, qreal y, qreal w, qreal h) {
    if (index < 0 || index >= int(clip_specs_.size())) return;
    pushUndo_(QStringLiteral("clip crop"), QStringLiteral("clipCrop:%1").arg(index));
    rift::ClipSpec& c = clip_specs_[index];
    c.cropX = qBound(0.0, double(x), 1.0);
    c.cropY = qBound(0.0, double(y), 1.0);
    c.cropW = qBound(0.02, double(w), 1.0);
    c.cropH = qBound(0.02, double(h), 1.0);
    pushClips_();
    update();
}

// Point the chain rail + params panel at a clip's own stack, or back at the master chain (-1).
void RiftViewport::selectClip(int index) {
    const int target = (index >= 0 && index < int(clip_specs_.size())) ? index : -1;
    if (target == edited_clip_) return;

    // First commit any changes on the currently edited clip
    if (edited_clip_ >= 0 && edited_clip_ < int(clip_specs_.size())) {
        syncChainToClip_();
    }

    if (target >= 0) {
        // Park the shared master chain if not already parked
        if (!d_->shared_parked) {
            std::lock_guard<std::mutex> lk(d_->params_mu);
            d_->shared_chain = d_->chain;
            d_->shared_parked = true;
        }
        edited_clip_ = target;

        // Load target clip's chain into d_->chain (empty if clip has no passes)
        {
            std::lock_guard<std::mutex> lk(d_->params_mu);
            d_->chain.clear();
            const auto& clipChain = clip_specs_[target].chain;
            for (const auto& pass : clipChain) {
                d_->chain.push_back({ QString::fromStdString(pass.shader),
                                      pass.params, {}, 0, pass.blend, pass.mix });
            }
            selected_ = d_->chain.empty() ? -1 : 0;
        }
        for (int i = 0; i < int(d_->chain.size()); ++i) loadManifest_(i);
    } else {
        // Deselect clip: restore shared master chain
        edited_clip_ = -1;
        if (d_->shared_parked) {
            std::lock_guard<std::mutex> lk(d_->params_mu);
            d_->chain = d_->shared_chain;
            d_->shared_chain.clear();
            d_->shared_parked = false;
            selected_ = d_->chain.empty() ? -1 : 0;
            d_->chain_dirty = true;
        }
        for (int i = 0; i < int(d_->chain.size()); ++i) loadManifest_(i);
    }

    publishParams_();
    emit chainChanged();
    emit effectChanged();
    emit clipsChanged();
    update();
}

void RiftViewport::syncChainToClip_() {
    if (edited_clip_ < 0 || edited_clip_ >= int(clip_specs_.size())) return;
    std::vector<rift::ChainPass> passes;
    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        passes.reserve(d_->chain.size());
        for (const auto& n : d_->chain) {
            passes.push_back({ n.effect.toStdString(), n.params, n.blend, n.mix });
        }
    }
    clip_specs_[edited_clip_].chain = std::move(passes);
    pushClips_();
    update();
}

void RiftViewport::duplicateClip(int index) {
    if (index < 0 || index >= int(clip_specs_.size())) return;
    pushUndo_(QStringLiteral("duplicate clip"), QString());

    // Copy everything: source, trim, blend, transform and the per-clip chain.
    rift::ClipSpec copy = clip_specs_[index];
    // start < 0 means "append after the previous clip in this lane", which is
    // where a duplicate belongs and saves the caller computing a position that
    // depends on a span only the engine knows.
    copy.start = -1.0;
    clip_specs_.push_back(copy);

    pushClips_();
    update();
}

void RiftViewport::splitClip(int index, qreal t) {
    if (index < 0 || index >= int(clip_specs_.size())) return;
    if (!d_->engine) return;

    const double start = d_->engine->clipStart(index);
    const double span  = d_->engine->clipSpan(index);
    // A cut needs material on both sides. A tenth of a second is below what
    // anyone would place deliberately and keeps both halves selectable.
    if (t <= start + 0.1 || t >= start + span - 0.1) {
        last_error_ = QStringLiteral("playhead is not inside the clip");
        return;
    }
    pushUndo_(QStringLiteral("split clip"), QString());

    const double cut = t - start;              // seconds into the clip
    rift::ClipSpec& a = clip_specs_[index];
    rift::ClipSpec  b = a;                     // effects and transform copied

    // Trims are positions in the SOURCE, so the second half starts where the
    // first one ends. Without this the cut would repeat the same footage.
    const double aIn = a.in;
    a.out = aIn + cut;
    b.in  = aIn + cut;
    b.start = t;

    // Inserting shifts every later index up by one, and edited_clip_ is such an
    // index - left alone, a split retargets the rail at the wrong clip.
    if (edited_clip_ > index) ++edited_clip_;
    clip_specs_.insert(clip_specs_.begin() + index + 1, b);
    pushClips_();
    update();
}

void RiftViewport::copyClip(int index) {
    if (index < 0 || index >= int(clip_specs_.size())) return;
    clipboard_ = clip_specs_[index];
    clipboard_valid_ = true;
    emit clipboardChanged();
}

void RiftViewport::pasteClip(qreal at, int lane) {
    if (!clipboard_valid_) return;
    pushUndo_(QStringLiteral("paste clip"), QString());

    rift::ClipSpec c = clipboard_;
    c.start = std::max(0.0, double(at));
    if (lane >= 0) c.lane = lane;
    clip_specs_.push_back(c);
    pushClips_();
    update();
}

void RiftViewport::fillTrack(int index) {
    if (index < 0 || index >= int(clip_specs_.size())) return;
    // The piece is as long as its audio. With no audio - stills, or a video
    // being cut silent - fall back to the track, so the button still does
    // something instead of refusing.
    double dur = d_->engine ? d_->engine->audioDuration() : 0.0;
    if (dur <= 0.0 && d_->engine) dur = d_->engine->timelineDuration();
    if (dur <= 0.0) {
        last_error_ = QStringLiteral("nothing to fill against yet");
        return;
    }
    pushUndo_(QStringLiteral("fill track"), QString());

    rift::ClipSpec& c = clip_specs_[index];
    c.start = 0.0;
    // out beyond the source length is deliberate: renderLayers_ wraps the
    // lookup, so the footage repeats for as long as the clip is asked to cover.
    c.in  = 0.0;
    c.out = dur;
    pushClips_();
    update();
}

void RiftViewport::setClipStart(int index, qreal start) {
    if (index < 0 || index >= int(clip_specs_.size())) return;
    pushUndo_(QStringLiteral("move clip"),
              QStringLiteral("clipStart:%1").arg(index));
    // Snap the clip's START to a beat - the edit users actually want on a
    // music-driven timeline. A no-op when snapping is off or nothing is close.
    clip_specs_[index].start = std::max(0.0, double(snapTime(start)));
    pushClips_();
    update();
}

void RiftViewport::setClipTrim(int index, qreal in, qreal out) {
    if (index < 0 || index >= int(clip_specs_.size())) return;
    pushUndo_(QStringLiteral("trim clip"),
              QStringLiteral("clipTrim:%1").arg(index));

    // in/out are positions INSIDE the source, but markers are timeline times.
    // Convert through the clip's resolved start so a trim handle snaps to the
    // beat the user sees under it, not to a source offset that happens to
    // share the number.
    const double oldIn = clip_specs_[index].in;
    // Resolved position, so an auto-appended clip (start < 0) shifts from where
    // it actually sits rather than from -1.
    double at = clip_specs_[index].start;
    if (d_->engine) at = d_->engine->clipStart(index);

    double newIn = std::max(0.0, double(in));
    double newOut = double(out);
    if (snap_) {
        const double inT  = snapTime(at + (newIn - oldIn));
        newIn = std::max(0.0, oldIn + (inT - at));
        if (newOut > newIn) {
            const double outT = snapTime(at + (newOut - oldIn));
            const double cand = oldIn + (outT - at);
            if (cand > newIn) newOut = cand;
        }
    }
    // Never trim the head past the tail: the clip would resolve to a zero or
    // negative span, which draws as nothing and cannot be grabbed again.
    if (newOut > 0.0 && newOut - newIn < 0.05) newIn = std::max(0.0, newOut - 0.05);

    // Trimming the head MOVES the clip's timeline position - that is what the
    // snapping above already assumes. Without shifting start, dragging the left
    // edge right left the head pinned in place and pulled the TAIL leftwards
    // instead, so the edge under the pointer was the one that did not move.
    const double headShift = newIn - oldIn;
    if (headShift != 0.0) clip_specs_[index].start = std::max(0.0, at + headShift);

    clip_specs_[index].in  = newIn;
    clip_specs_[index].out = newOut;
    pushClips_();
    update();
}

// ── audio-track clips (Phase 1) ────────────────────────────────────────────
// Mirror of the video-clip editing surface: same gestures, same undo pattern,
// no per-clip chain (audio has no effect stack).

void RiftViewport::addAudioClip(const QUrl& url, int lane, int link) {
    const QString path = url.isLocalFile() ? url.toLocalFile() : url.toString();
    if (path.isEmpty()) return;
    pushUndo_(QStringLiteral("add audio"), QStringLiteral("addAudioClip"));

    rift::AudioClipSpec a;
    a.path   = path.toStdString();
    a.name   = QFileInfo(path).fileName().toStdString();
    a.start  = -1.0;            // append on this lane; the engine resolves it
    a.lane   = lane;
    a.link   = link;
    a.gain   = 1.0;
    audio_clip_specs_.push_back(a);
    has_audio_ = true;
    pushAudioClips_();
    emit sourceChanged();
    update();
}

void RiftViewport::removeAudioClip(int index) {
    if (index < 0 || index >= int(audio_clip_specs_.size())) return;
    pushUndo_(QStringLiteral("remove audio"), QStringLiteral("removeAudio"));
    audio_clip_specs_.erase(audio_clip_specs_.begin() + index);
    pushAudioClips_();
    update();
}

void RiftViewport::setAudioClipStart(int index, qreal start) {
    if (index < 0 || index >= int(audio_clip_specs_.size())) return;
    pushUndo_(QStringLiteral("move audio"),
              QStringLiteral("audioStart:%1").arg(index));
    audio_clip_specs_[index].start = std::max(0.0, double(start));
    pushAudioClips_();
    update();
}

void RiftViewport::setAudioClipTrim(int index, qreal in, qreal out) {
    if (index < 0 || index >= int(audio_clip_specs_.size())) return;
    pushUndo_(QStringLiteral("trim audio"),
              QStringLiteral("audioTrim:%1").arg(index));

    rift::AudioClipSpec& a = audio_clip_specs_[index];
    const double oldIn = a.in;
    double newIn  = std::max(0.0, double(in));
    double newOut = double(out);
    // Never let the head pass the tail: a zero-span clip draws nothing and
    // cannot be grabbed again, same rule as the video trims.
    if (newOut > 0.0 && newOut - newIn < 0.05)
        newIn = std::max(0.0, newOut - 0.05);
    // Trimming the head moves the clip's timeline position, like the video
    // trims do.
    const double headShift = newIn - oldIn;
    if (headShift != 0.0 && a.start >= 0.0)
        a.start = std::max(0.0, a.start + headShift);
    a.in  = newIn;
    a.out = newOut;
    pushAudioClips_();
    update();
}

void RiftViewport::setAudioClipLane(int index, int lane) {
    if (index < 0 || index >= int(audio_clip_specs_.size())) return;
    pushUndo_(QStringLiteral("audio lane"), QStringLiteral("audioLane:%1").arg(index));
    audio_clip_specs_[index].lane = std::max(0, lane);
    if (audio_clip_specs_[index].start < 0.0 && d_->engine)
        audio_clip_specs_[index].start =
            d_->engine->audioClipStart(index);
    pushAudioClips_();
    update();
}

void RiftViewport::setAudioClipGain(int index, qreal gain) {
    if (index < 0 || index >= int(audio_clip_specs_.size())) return;
    pushUndo_(QStringLiteral("audio gain"),
              QStringLiteral("audioGain:%1").arg(index));
    // Linear internally; the UI shows dB. Gain does not change placement, so
    // no structural re-push is needed for the layout - but it does change the
    // mix, which the engine applies immediately.
    audio_clip_specs_[index].gain = qBound(0.0, double(gain), 2.0);
    pushAudioClips_();
    update();
}

void RiftViewport::splitAudioClip(int index, qreal t) {
    if (index < 0 || index >= int(audio_clip_specs_.size())) return;
    if (!d_->engine) return;

    const double start = d_->engine->audioClipStart(index);
    const double span  = d_->engine->audioClipSpan(index);
    if (t <= start + 0.1 || t >= start + span - 0.1) {
        last_error_ = QStringLiteral("playhead is not inside the clip");
        return;
    }
    pushUndo_(QStringLiteral("split audio"), QString());

    const double cut = t - start;
    rift::AudioClipSpec& a = audio_clip_specs_[index];
    rift::AudioClipSpec  b = a;

    // Trims are source positions, so the second half starts where the first
    // one ends, and the first half now ends there.
    const double aIn = a.in;
    a.out = aIn + cut;
    b.in  = aIn + cut;
    b.start = t;

    audio_clip_specs_.insert(audio_clip_specs_.begin() + index + 1, b);
    pushAudioClips_();
    update();
}

// One place that hands the whole track to the engine and refreshes the model.
// Have any resolved clip positions changed since the model was last built?
//
// clipStart/clipSpan come from the engine's layout, which settles as decoders
// open. Comparing against what the model already holds is a handful of doubles
// and saves rebuilding every delegate in the timeline.
bool RiftViewport::clipLayoutMoved_() const {
    if (!d_->engine) return false;
    if (clips_ui_.size() != int(clip_specs_.size())) return true;
    for (int i = 0; i < clips_ui_.size(); ++i) {
        const QVariantMap m = clips_ui_[i].toMap();
        if (std::abs(m.value(QStringLiteral("start")).toDouble()
                     - d_->engine->clipStart(i)) > 1e-3) return true;
        if (std::abs(m.value(QStringLiteral("span")).toDouble()
                     - d_->engine->clipSpan(i)) > 1e-3) return true;
    }
    return false;
}

bool RiftViewport::audioClipLayoutMoved_() const {
    if (!d_->engine) return false;
    if (audio_clips_ui_.size() != int(audio_clip_specs_.size())) return true;
    for (int i = 0; i < audio_clips_ui_.size(); ++i) {
        const QVariantMap m = audio_clips_ui_[i].toMap();
        if (std::abs(m.value(QStringLiteral("start")).toDouble()
                     - d_->engine->audioClipStart(i)) > 1e-3) return true;
        if (std::abs(m.value(QStringLiteral("span")).toDouble()
                     - d_->engine->audioClipSpan(i)) > 1e-3) return true;
    }
    return false;
}

void RiftViewport::pushClips_() {
    if (d_->engine) d_->engine->setClips(clip_specs_);

    clips_ui_.clear();
    for (int i = 0; i < int(clip_specs_.size()); ++i) {
        const auto& c = clip_specs_[i];
        QVariantMap m;
        m[QStringLiteral("index")] = i;
        m[QStringLiteral("path")]  = QString::fromStdString(c.path);
        m[QStringLiteral("isText")] = (c.kind == rift::ClipSpec::Text);
        // Text clips have no filename, so the timeline labels them with the
        // text itself - otherwise every one of them reads as a blank block.
        m[QStringLiteral("name")]  = (c.kind == rift::ClipSpec::Text)
            ? (c.text.text.empty() ? QStringLiteral("(empty text)")
                                   : QStringLiteral("T: ")
                                     + QString::fromStdString(c.text.text).left(24))
            : QFileInfo(QString::fromStdString(c.path)).fileName();
        m[QStringLiteral("in")]    = c.in;
        m[QStringLiteral("out")]   = c.out;
        m[QStringLiteral("lane")]    = c.lane;
        m[QStringLiteral("blend")]   = c.blend;
        m[QStringLiteral("opacity")] = c.opacity;
        m[QStringLiteral("posX")]    = c.posX;
        m[QStringLiteral("posY")]    = c.posY;
        m[QStringLiteral("scale")]   = c.scale;
        m[QStringLiteral("cropX")]   = c.cropX;
        m[QStringLiteral("cropY")]   = c.cropY;
        m[QStringLiteral("cropW")]   = c.cropW;
        m[QStringLiteral("cropH")]   = c.cropH;
        m[QStringLiteral("chainLen")] = int(c.chain.size());
        m[QStringLiteral("edited")]  = (i == edited_clip_);
        // Draw where the engine says the clip actually is, not where the UI
        // guessed: auto-append positions and real durations resolve there.
        m[QStringLiteral("start")] = d_->engine ? d_->engine->clipStart(i) : c.start;
        m[QStringLiteral("span")]  = d_->engine ? d_->engine->clipSpan(i)  : 0.0;
        clips_ui_.append(m);
    }
    emit clipsChanged();
}

void RiftViewport::pushAudioClips_() {
    if (d_->engine) d_->engine->setAudioClips(audio_clip_specs_);

    audio_clips_ui_.clear();
    for (int i = 0; i < int(audio_clip_specs_.size()); ++i) {
        const auto& c = audio_clip_specs_[i];
        QVariantMap m;
        m[QStringLiteral("index")] = i;
        m[QStringLiteral("path")]  = QString::fromStdString(c.path);
        m[QStringLiteral("name")]  = c.name.empty()
            ? QFileInfo(QString::fromStdString(c.path)).fileName()
            : QString::fromStdString(c.name);
        m[QStringLiteral("in")]    = c.in;
        m[QStringLiteral("out")]   = c.out;
        m[QStringLiteral("lane")]  = c.lane;
        m[QStringLiteral("gain")]  = c.gain;
        m[QStringLiteral("link")]  = c.link;
        m[QStringLiteral("start")] =
            d_->engine ? d_->engine->audioClipStart(i) : c.start;
        m[QStringLiteral("span")]  =
            d_->engine ? d_->engine->audioClipSpan(i) : 0.0;
        audio_clips_ui_.append(m);
    }
    audio_lane_count_ = d_->engine ? d_->engine->audioLaneCount() : 1;
    emit clipsChanged();
}

void RiftViewport::loadAudio(const QUrl& audioUrl, const QUrl& analysisUrl) {
    const QString a = audioUrl.isLocalFile() ? audioUrl.toLocalFile()
                                             : audioUrl.toString();
    const QString an = analysisUrl.isLocalFile() ? analysisUrl.toLocalFile()
                                                 : QString();
    audio_clip_specs_.clear();
    if (!a.isEmpty()) {
        rift::AudioClipSpec x;
        x.path  = a.toStdString();
        x.name  = QFileInfo(a).fileName().toStdString();
        x.start = 0.0;
        x.lane  = 0;
        audio_clip_specs_.push_back(x);
    }
    d_->pending_audio_path = a;
    d_->pending_analysis_path = an;
    if (d_->engine) d_->engine->loadAudio(a.toStdString(), an.toStdString());
    has_audio_ = !a.isEmpty();
    pushAudioClips_();
    emit sourceChanged();
    update();
}
void RiftViewport::play() {
    if (d_->engine) d_->engine->play();
    playing_ = true;  emit transportChanged(); update();
}
void RiftViewport::pause() {
    if (d_->engine) d_->engine->pause();
    playing_ = false; emit transportChanged(); update();
}
void RiftViewport::setLiveInput(bool on) {
    if (live_input_ == on) return;
    // The same rule from the other side: start listening and the file stops.
    if (on && playing_) pause();
    live_input_ = on;
    // Queued inside Engine; also remembered so it survives the lazy Engine
    // build (the toggle can be hit before the first frame).
    if (d_->engine) d_->engine->setLiveInput(on);
    d_->pending_live = on;
    d_->pending_live_set = true;
    emit sourceChanged();
    update();
}

void RiftViewport::seek(double seconds) {
    if (d_->engine) d_->engine->seek(seconds);
    playhead_ = seconds;
    emit transportChanged();
    update();
}

// GUI thread, every tick: mirror engine state into the QML-facing properties.
// Reads are plain scalars the render thread publishes; no locking, and a value
// one frame stale is fine for a readout.
void RiftViewport::pollEngine_() {
    if (!d_->engine) return;

    const double ph = d_->engine->playhead();
    if (!qFuzzyCompare(ph + 1.0, playhead_ + 1.0)) {
        playhead_ = ph;
        emit transportChanged();
        refreshKeyState_();      // cheap; only signals when the answer changes
        refreshGradeKeyState_();
    }

    rift_stats st{};
    d_->engine->stats(st);
    // One signal for the whole group: these are read together, and emitting
    // per field would wake every binding four times a tick.
    if (!qFuzzyCompare(st.fps + 1.0, fps_ + 1.0)
        || !qFuzzyCompare(st.frame_ms_p95 + 1.0, frame_p95_ + 1.0)
        || !qFuzzyCompare(st.frame_ms_max + 1.0, frame_max_ + 1.0)
        || !qFuzzyCompare(st.gpu_ms + 1.0, gpu_ms_ + 1.0)) {
        fps_       = st.fps;
        frame_p95_ = st.frame_ms_p95;
        frame_max_ = st.frame_ms_max;
        gpu_ms_    = st.gpu_ms;
        emit statsChanged();
    }

    const bool m = d_->engine->mediaReady();
    const bool a = d_->engine->audioReady();
    if (m != has_media_ || a != has_audio_) {
        has_media_ = m; has_audio_ = a;
        emit sourceChanged();
    }

    const bool p = d_->engine->playing();
    if (p != playing_) { playing_ = p; emit transportChanged(); }

    // Live input can fail to open a capture device, so mirror the engine's
    // actual state rather than assuming the request succeeded.
    const bool li = d_->engine->liveInput();
    if (li != live_input_) { live_input_ = li; emit sourceChanged(); }
    live_level_ = double(d_->engine->liveLevel());

    // Track length only becomes known once clips open, so poll it and refresh
    // the strip's scale when it settles.
    // A real epsilon, not qFuzzyCompare: on a duration of a couple of hundred
    // seconds qFuzzyCompare is accurate to about a picosecond, so a value that
    // wobbles in its last bits re-entered this branch on EVERY frame - and the
    // branch rebuilds the whole clip model. A millisecond is far below anything
    // visible on a timeline.
    const double td = d_->engine->timelineDuration();
    if (std::abs(td - track_dur_) > 1e-3) {
        track_dur_ = td;
        emit durationChanged();
        // Only rebuild the model if the clips actually MOVED. The total length
        // changes while a decoder is still resolving a span, and rebuilding
        if (!clip_dragging_ && clipLayoutMoved_()) pushClips_();
        if (audioClipLayoutMoved_()) pushAudioClips_();
    }
    const int ac = d_->engine->activeClip();
    if (ac != active_clip_) { active_clip_ = ac; emit transportChanged(); }
    const int lc = d_->engine->laneCount();
    if (lc != lane_count_) { lane_count_ = lc; emit clipsChanged(); }
    const int alc = d_->engine->audioLaneCount();
    if (alc != audio_lane_count_) { audio_lane_count_ = alc; emit clipsChanged(); }
    if (audioClipLayoutMoved_()) pushAudioClips_();

    // Waveform appears once the audio finishes loading, so poll until it does
    // rather than assuming it is ready at load time.
    //
    // Keyed on the engine's load GENERATION, not on the waveform's length:
    // buildWaveform_ always produces the same bucket count, so loading a second
    // track left the size unchanged and the timeline kept drawing - and snapping
    // to - the first track's peaks and beats. Also keeps the copy off the hot
    // path, since nothing is fetched until the generation actually moves.
    const uint32_t gen = d_->engine->audioDataGeneration();
    if (gen != audio_gen_) {
        audio_gen_ = gen;
        const std::vector<float> wf = d_->engine->waveform();
        wave_ui_.clear();
        wave_ui_.reserve(int(wf.size()));
        for (float v : wf) wave_ui_.append(double(v));
        emit waveformChanged();

        // Beats land with the waveform (both are built by the same load), so
        // adopt them here - unless markers were edited by hand, which must not
        // be thrown away by a poll.
        if (!markers_edited_) {
            const std::vector<double> bt = d_->engine->beats();
            markers_.assign(bt.begin(), bt.end());
            bpm_ = double(d_->engine->bpm());
            publishMarkers_();
        }
    }

    // Live channel levels for the meters. Published every tick while playing so
    // the rack visibly reacts; when stopped, publish once so it settles to rest.
    rift_channel_frame cf{};
    d_->engine->channels(cf);
    bool changed = levels_.size() != RIFT_CH_COUNT;
    if (levels_.size() != RIFT_CH_COUNT) {
        levels_.clear();
        for (int i = 0; i < RIFT_CH_COUNT; ++i) levels_.append(0.0);
    }
    for (int i = 0; i < RIFT_CH_COUNT; ++i) {
        const double v = double(cf.ch[i]);
        if (!qFuzzyCompare(v + 1.0, levels_.at(i).toDouble() + 1.0)) {
            levels_[i] = v;
            changed = true;
        }
    }
    if (changed) emit levelsChanged();
}

// ── render thread ─────────────────────────────────────────────────────────
void RiftViewport::ensureEngine_() {
    if (d_->failed || d_->engine) return;
    if (shader_dir_.isEmpty()) return;

    auto* ri = window()->rendererInterface();
    auto* qrhi = static_cast<QRhi*>(
        ri->getResource(window(), QSGRendererInterface::RhiResource));
    if (!qrhi) {
        qWarning("RiftViewport: Qt Quick exposed no QRhi - the RHI backend "
                 "(Direct3D11) must be set before QGuiApplication is created");
        d_->failed = true;
        return;
    }

    d_->engine = std::make_unique<rift::Engine>(
        shader_dir_.toStdString(), shader_dir_.toStdString(), qrhi);
    if (!d_->engine->rhiContext() || !d_->engine->rhiContext()->valid()) {
        d_->failed = true;
        d_->engine.reset();
        return;
    }

    // Replay anything the UI asked for before the Engine existed.
    if (!d_->replayed) {
        d_->replayed = true;
        if (!clip_specs_.empty()) d_->engine->setClips(clip_specs_);
        if (!d_->pending_audio_path.isEmpty())
            d_->engine->loadAudio(d_->pending_audio_path.toStdString(),
                                  d_->pending_analysis_path.toStdString());
        if (!grade_params_.empty()) d_->engine->setGrade(grade_params_);
        if (d_->pending_live_set) d_->engine->setLiveInput(d_->pending_live);
        if (playing_) d_->engine->play();
        for (int i = 0; i < 4; ++i) bakeAndUploadLut_(i);
    }
}

#define RVTRACE(msg) do { if (qEnvironmentVariableIsSet("RIFT_UI_DBG")) \
    { fprintf(stderr, "[RiftViewport] " msg "\n"); fflush(stderr); } } while (0)

void RiftViewport::onBeforeRendering() {
    if (width() <= 0 || height() <= 0) return;
    RVTRACE("ensureEngine begin");
    ensureEngine_();
    RVTRACE("ensureEngine done");
    if (d_->failed || !d_->engine) return;

    {
        std::lock_guard<std::mutex> lk(d_->params_mu);
        const auto& master = (edited_clip_ >= 0 && d_->shared_parked)
                           ? d_->shared_chain : d_->chain;

        if (d_->chain_dirty) {
            RVTRACE("chain rebuild begin");
            auto& g = d_->engine->graph();
            g.clear();
            // source -> fx0 -> fx1 -> ... in list order: each node reads the
            // previous node's output, so the list IS the render order.
            uint32_t prev = g.addSource();
            for (const auto& n : master) {
                uint32_t gid = g.addEffect(n.effect.toStdString());
                g.connect(prev, gid);
                if (!n.params.empty()) g.setParams(gid, n.params);
                g.setBlend(gid, n.blend, n.mix);
                if (qEnvironmentVariableIsSet("RIFT_UI_DBG"))
                    fprintf(stderr, "[chain] %s gid=%u prev=%u params=%zu\n",
                            qPrintable(n.effect), gid, prev, n.params.size()),
                    fflush(stderr);
                prev = gid;
            }
            // Structural change: pipelines must be recompiled before execute().
            g.build(*d_->engine->rhiContext());
            d_->chain_dirty = false;
            d_->params_dirty = false;
            RVTRACE("chain rebuild done");
        } else if (d_->params_dirty && edited_clip_ < 0) {
            for (auto& n : d_->chain)
                if (n.gid && !n.params.empty())
                    d_->engine->graph().setParams(n.gid, n.params);
            d_->params_dirty = false;
        }
    }

    // Render at DEVICE pixels, not logical ones. width()/height() are in Qt's
    // layout units; on a display running at 125/150/175% scaling the window's
    // framebuffer is that much larger, so rendering at the logical size and
    // letting the scene graph stretch it up is a straight resolution loss -
    // the picture reads as soft and blocky no matter what the effect does.
    const qreal dpr = window() ? window()->effectiveDevicePixelRatio() : 1.0;
    const QRectF fr = framedRect();
    if (fr.isEmpty()) return;

    int devW = std::max(2, int(fr.width()  * dpr + 0.5));
    if (devW % 2 != 0) devW++;
    int devH = std::max(2, int(fr.height() * dpr + 0.5));
    if (devH % 2 != 0) devH++;

    const QSize want{ devW, devH };
    if (want != d_->size) { d_->size = want; d_->sg_scene = 0; }

    // The placeholder source for an empty track lives in Engine, so the export
    // renders over the same thing the viewport shows.
    RVTRACE("renderExternal begin");
    d_->scene = d_->engine->renderExternal(d_->size.width(), d_->size.height());
    RVTRACE("renderExternal done");
    // No update() here - this is the render thread, where it is a no-op.
    // The GUI-thread timer requests the next frame.
}

QSGNode* RiftViewport::updatePaintNode(QSGNode* old, UpdatePaintNodeData*) {
    if (d_->failed || !d_->engine || !d_->scene || d_->size.isEmpty()) {
        if (qEnvironmentVariableIsSet("RIFT_UI_DBG"))
            fprintf(stderr, "[RiftViewport] paintNode SKIP failed=%d engine=%d "
                    "scene=%u empty=%d\n", int(d_->failed), int(!!d_->engine),
                    d_->scene, int(d_->size.isEmpty())), fflush(stderr);
        delete old;
        d_->sg_scene = 0;       // wrapper died with the node
        return nullptr;
    }
    RVTRACE("paintNode building");

    auto* node = static_cast<QSGSimpleTextureNode*>(old);
    if (!node) {
        node = new QSGSimpleTextureNode;
        node->setFiltering(QSGTexture::Linear);
        node->setOwnsTexture(true);
    }

    // The scene texture can be a rotating target, so its id changes with the
    // chain length and with how many clips are stacked. Rewrap only when the id
    // actually changed - rewrapping every frame is wasteful, and never
    // rewrapping shows a stale pass.
    //
    // `node->texture()` is the source of truth for "is a wrapper installed",
    // so a node Qt handed us fresh (or one we just built) is always given one.
    if (d_->scene != d_->sg_scene || !node->texture()) {
        auto* rt = static_cast<QRhiTexture*>(
            d_->engine->rhiContext()->textureHandle(d_->scene));
        if (!rt) {
            RVTRACE("  no QRhiTexture for scene");
            delete node;
            d_->sg_scene = 0;
            return nullptr;
        }
        // One shared QRhi, so the scene graph wraps engine output directly -
        // no copy, no readback.
        QSGTexture* wrap = window()->createTextureFromRhiTexture(rt);
        // createTextureFromRhiTexture() hands OWNERSHIP of the QRhiTexture to
        // the wrapper, and RhiContext already owns it. Whenever Qt destroyed a
        // wrapper it deleted a live engine target, and the next use of that id
        // read freed memory. Disown it: the engine is the only owner.
        if (auto* plain = static_cast<QSGPlainTexture*>(wrap))
            plain->setOwnsTexture(false);
        node->setTexture(wrap);
        d_->sg_scene = d_->scene;
    }

    const QRectF fr = framedRect();
    node->setRect(fr.x(), fr.y(), fr.width(), fr.height());
    return node;
}
