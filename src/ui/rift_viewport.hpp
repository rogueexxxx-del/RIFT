// RiftViewport - QQuickItem that shows the live engine render inside QML.
//
// Owns the Engine in external-render mode. It has to: a QRhiTexture belongs to
// the device that created it, so engine output can only reach the scene graph
// if the engine renders on Qt Quick's device - and this item is where that
// device becomes available. Putting the Engine anywhere else means shipping
// textures across devices, which is a copy at best.
//
// Threading: this object lives on the GUI thread; everything touching the QRhi
// runs on the scene-graph render thread (onBeforeRendering). The handoff point
// is updatePaintNode(), the one place Qt guarantees both threads are blocked.
// QML-facing calls (play, loadMedia, ...) come from the GUI thread and forward
// straight into Engine, matching how the C API was already meant to be used.
#pragma once
#include <QQuickItem>
#include <QSize>
#include <QUrl>
#include <QVariantList>
#include <QJsonObject>
#include <QStringList>
#include <QHash>
#include <QTimer>
#include <QRectF>
#include <memory>
#include <vector>
#include "timeline.hpp"
#include "control_input.hpp"
#include "rift/rift_types.h"
// Full definition, not a forward declaration: ExportJob stores
// Engine::ChainNode by value.
#include "engine.hpp"

class RiftViewport : public QQuickItem {
    Q_OBJECT
    QML_ELEMENT
    // Where the .qsb shaders live. Must be set before the first frame.
    Q_PROPERTY(QString shaderDir READ shaderDir WRITE setShaderDir NOTIFY shaderDirChanged)
    // Effect id of the SELECTED chain node ("ascii", "halftone", ...). Setting
    // it replaces that node's effect.
    Q_PROPERTY(QString effect READ effect WRITE setEffect NOTIFY effectChanged)
    // The effect chain, in render order: [{effect, label, selected}]. Source
    // and output are implicit - this is the editable middle.
    Q_PROPERTY(QVariantList chain READ chain NOTIFY chainChanged)
    Q_PROPERTY(int selectedNode READ selectedNode WRITE setSelectedNode NOTIFY chainChanged)
    Q_PROPERTY(bool  playing  READ playing  NOTIFY transportChanged)
    Q_PROPERTY(double playhead READ playhead NOTIFY transportChanged)
    Q_PROPERTY(double fps      READ fps      NOTIFY statsChanged)
    // Worst-case frame times over a rolling window, and GPU time. An average
    // fps hides exactly the thing people complain about: 59 good frames and
    // one 200 ms hitch still reads as a comfortable 60.
    Q_PROPERTY(double frameP95 READ frameP95 NOTIFY statsChanged)
    Q_PROPERTY(double frameMax READ frameMax NOTIFY statsChanged)
    Q_PROPERTY(double gpuMs    READ gpuMs    NOTIFY statsChanged)
    // Per-effect parameter metadata for the panel: one entry per uniform with
    // name/label/min/max/step/value. Rebuilt when the effect changes.
    Q_PROPERTY(QVariantList params READ params NOTIFY paramsChanged)
    // Audio channels the patch bay can drive a uniform from. Static list of
    // {name, key}; index matches rift_channel / rift_channel_frame::ch[].
    Q_PROPERTY(QVariantList channelNames READ channelNames CONSTANT)
    // Live smoothed channel levels, one per channel, refreshed every tick.
    // This is the "reactivity" readout: what the audio is doing right now.
    Q_PROPERTY(QVariantList channelLevels READ channelLevels NOTIFY levelsChanged)
    Q_PROPERTY(bool exporting     READ exporting     NOTIFY exportChanged)
    Q_PROPERTY(int  exportPercent READ exportPercent NOTIFY exportChanged)
    Q_PROPERTY(QString exportStatus READ exportStatus NOTIFY exportChanged)
    // Live mic/loopback input drives the channels instead of an .analysis blob.
    Q_PROPERTY(bool liveInput READ liveInput WRITE setLiveInput NOTIFY sourceChanged)
    Q_PROPERTY(qreal liveLevel READ liveLevel NOTIFY levelsChanged)
    // The clip track: [{name, path, start, in, out, span, active}].
    Q_PROPERTY(QVariantList clips READ clips NOTIFY clipsChanged)
    Q_PROPERTY(qreal trackDuration READ trackDuration NOTIFY durationChanged)
    Q_PROPERTY(int laneCount READ laneCount NOTIFY clipsChanged)
    // The audio-track clips (A1..An), same shape as `clips` so the timeline
    // renders both bands with near-identical delegates:
    // [{name, path, start, in, out, span, lane, gain, link, edited}].
    Q_PROPERTY(QVariantList audioClips READ audioClips NOTIFY clipsChanged)
    Q_PROPERTY(int audioLaneCount READ audioLaneCount NOTIFY clipsChanged)
    // Which clip is currently selected in the timeline (-1 = none).
    Q_PROPERTY(int editedClip READ editedClip NOTIFY clipsChanged)
    Q_PROPERTY(int selectedClip READ selectedClip WRITE selectClip NOTIFY clipsChanged)
    // Peak envelope of the loaded audio, 0..1 across the whole track. Static
    // once loaded, so the timeline can cache it.
    Q_PROPERTY(QVariantList waveform READ waveform NOTIFY waveformChanged)
    // ── beat / onset markers ──
    // Times in seconds. Detected from the audio at load, plus anything tapped
    // in by hand. Sorted, so the timeline can draw and snap without resorting.
    Q_PROPERTY(QVariantList markers READ markers NOTIFY markersChanged)
    Q_PROPERTY(bool snapToMarkers READ snapToMarkers WRITE setSnapToMarkers
               NOTIFY markersChanged)
    Q_PROPERTY(qreal bpm READ bpm NOTIFY markersChanged)
    // Keys of the selected node, flattened for the keyframe lane:
    // [{param, paramLabel, time, value, interp}].
    Q_PROPERTY(QVariantList keyframes READ keyframes NOTIFY paramsChanged)
    // One bool per parameter: is there a key at the playhead right now? Kept
    // SEPARATE from `params` on purpose - this changes as time moves, and
    // folding it into the params model reset the whole ListView every frame
    // (rebuilding every slider), which cost ~55 fps.
    Q_PROPERTY(QVariantList keyedNow READ keyedNow NOTIFY keyStateChanged)
    Q_PROPERTY(QVariantList keyInterpNow READ keyInterpNow NOTIFY keyStateChanged)
    // Master colour grade, same shape as `params` so the panel reuses sliders.
    Q_PROPERTY(QVariantList grade READ grade NOTIFY gradeChanged)
    // Which clip the playhead is inside, -1 in a gap. Drives the strip's
    // highlight so it is obvious which source is on screen.
    Q_PROPERTY(int activeClipIndex READ activeClipIndex NOTIFY transportChanged)
    Q_PROPERTY(bool hasMedia   READ hasMedia NOTIFY sourceChanged)
    Q_PROPERTY(bool hasAudio   READ hasAudio NOTIFY sourceChanged)
    Q_PROPERTY(QString mediaName READ mediaName NOTIFY sourceChanged)

public:
    explicit RiftViewport(QQuickItem* parent = nullptr);
    ~RiftViewport() override;

    // ── text layers ──
    // A text clip is a normal clip whose source is rasterized text, so it goes
    // through the same chain, blend modes, lanes, keyframes and audio bindings
    // as footage. Reactivity is whatever effects you put on it.
    // NOTE: these must stay in a `public:` section. Everything above the first
    // access specifier is private, and QML cannot call a private Q_INVOKABLE -
    // it fails at runtime with "is not a function", not at compile time.
    Q_INVOKABLE void addTextClip(const QString& text, int lane = 1,
                                 qreal seconds = 5.0);
    Q_INVOKABLE void setClipText(int index, const QString& text);
    // size/x/y are fractions of the frame; colour is 0..1 per channel.
    Q_INVOKABLE void setClipTextStyle(int index, qreal size, qreal x, qreal y,
                                      qreal r, qreal g, qreal b,
                                      bool bold = false,
                                      qreal letterSpacing = 0.0,
                                      qreal wrapWidth = 0.0,
                                      const QString& font = QString());
    Q_INVOKABLE QVariantMap clipText(int index) const;

    // Every font installed on this machine, for the text-layer and UI pickers.
    // The rasteriser resolves a family by name at render time, so anything in
    // this list can be used in a title - and in an export, which rasterises
    // through the same path.
    Q_INVOKABLE QStringList systemFonts() const;

    // Relaunch the app. A font change applies live, but anything Qt already
    // laid out with metrics from the old family keeps them until it is rebuilt,
    // so the offer to restart is how the change lands everywhere at once.
    Q_INVOKABLE void restartApp();

    // ── workspace mode ──
    // 0 = React (timeline, keyframes, export), 1 = Live (perform with a
    // controller). Only a UI concept - the engine renders the same either
    // way - but it is saved with the project so a set opens back the way it
    // was left.
    Q_PROPERTY(int mode READ mode WRITE setMode NOTIFY modeChanged)
    int  mode() const { return mode_; }
    void setMode(int m);
    // File the project was last saved to or opened from, "" when untitled.
    // Export range. Both in seconds; markOut <= markIn means "no range set",
    // which is how a fresh project and an old .rt file both behave.
    // The shape the piece is composed for. Index into the export dialog's
    // ratio list; stored on the project so the export defaults to what was
    // actually framed rather than to 16:9.
    Q_PROPERTY(int projectAspect READ projectAspect WRITE setProjectAspect
               NOTIFY projectChanged)
    int  projectAspect() const { return project_aspect_; }
    void setProjectAspect(int a);

    Q_PROPERTY(QRectF framedRect READ framedRect NOTIFY framedRectChanged)
    QRectF framedRect() const;

    Q_PROPERTY(double markIn  READ markIn  NOTIFY marksChanged)
    Q_PROPERTY(double markOut READ markOut NOTIFY marksChanged)
    double markIn()  const { return mark_in_; }
    double markOut() const { return mark_out_; }
    Q_INVOKABLE void setMarkIn(double t);
    Q_INVOKABLE void setMarkOut(double t);
    Q_INVOKABLE void clearMarks();

    Q_PROPERTY(QString projectPath READ projectPath NOTIFY projectChanged)
    Q_PROPERTY(QString projectName READ projectName NOTIFY projectChanged)
    QString projectPath() const { return project_path_; }
    QString projectName() const;
    // Name typed in the New-project dialog, used until the project is first
    // saved and gets a real path.
    // ---- preset library ----
    // A preset is a project saved WITHOUT clips, so it drops a look onto
    // whatever footage is already loaded. These live in the user's app data
    // rather than wherever a file dialog last pointed, so they are always
    // there to pick from.
    // Live audio sources. Entries are { name, loopback } - a loopback source
    // is the mix being sent to an output device, which is how a DAW or any
    // other program becomes the audio input with no routing to set up.
    Q_INVOKABLE QVariantList liveDevices();
    Q_INVOKABLE void setLiveDevice(int index);
    Q_PROPERTY(int liveDevice READ liveDevice WRITE setLiveDevice NOTIFY sourceChanged)
    int liveDevice() const { return live_device_; }

    Q_INVOKABLE QVariantList presets() const;
    Q_INVOKABLE bool savePresetNamed(const QString& name);
    Q_INVOKABLE bool applyPreset(const QString& path);
    Q_INVOKABLE bool deletePreset(const QString& path);
    Q_INVOKABLE bool renamePreset(const QString& oldPath, const QString& newName);
    Q_INVOKABLE bool duplicatePreset(const QString& path);
    Q_INVOKABLE QString presetsFolder() const;
    Q_PROPERTY(QVariantList presetList READ presets NOTIFY presetsChanged)

    Q_INVOKABLE void setProjectTitle(const QString& t) {
        if (project_title_ == t) return;
        project_title_ = t;
        emit projectChanged();
    }

    QString shaderDir() const { return shader_dir_; }
    void    setShaderDir(const QString&);
    QString effect() const;            // selected node's effect
    void    setEffect(const QString&); // replaces the selected node's effect

    bool   playing() const  { return playing_; }
    double playhead() const { return playhead_; }
    double fps() const      { return fps_; }
    double frameP95() const { return frame_p95_; }
    double frameMax() const { return frame_max_; }
    double gpuMs() const    { return gpu_ms_; }
    QVariantList clips() const { return clips_ui_; }
    qreal  trackDuration() const { return track_dur_; }
    int    laneCount() const { return lane_count_; }
    QVariantList audioClips() const { return audio_clips_ui_; }
    int    audioLaneCount() const { return audio_lane_count_; }
    int    editedClip() const { return edited_clip_; }
    int    selectedClip() const { return edited_clip_; }
    QVariantList waveform() const { return wave_ui_; }
    QVariantList markers() const { return markers_ui_; }
    bool  snapToMarkers() const { return snap_; }
    void  setSnapToMarkers(bool on);
    qreal bpm() const { return bpm_; }

    // Nearest marker to `t`, or `t` itself when snapping is off or nothing is
    // within reach. `tolerance` is in seconds - the caller converts from pixels
    // so the grab distance stays constant on screen at any zoom.
    Q_INVOKABLE qreal snapTime(qreal t, qreal tolerance = 0.15) const;
    Q_INVOKABLE void addMarker(qreal t);       // tap one in by hand
    Q_INVOKABLE void removeMarkerNear(qreal t, qreal tolerance = 0.15);
    Q_INVOKABLE void clearMarkers();
    // Re-run detection on the loaded audio, e.g. after changing sensitivity.
    Q_INVOKABLE void detectMarkers();
    // Drop a key on every marker inside the clip - the point of having them.
    Q_INVOKABLE int keyOnMarkers(int paramIndex);
    QVariantList keyframes() const;
    QVariantList keyedNow() const { return keyed_now_; }
    QVariantList keyInterpNow() const;
    QVariantList grade() const { return grade_ui_; }
    Q_INVOKABLE void setGradeParam(int index, qreal value);
    Q_INVOKABLE void resetGrade();

    // ── grade automation ──
    // The grade is resolved through the SAME resolve() the effect uniforms go
    // through (LayerStack::applyGrade), and the project format already round
    // trips its bindings and keys - so audio patching and keyframes worked on
    // the engine side all along with no way to reach them. These mirror the
    // chain-side calls one for one, so ColorPanel can reuse PatchRow and the
    // keyframe row instead of growing a second kind of parameter control.
    Q_INVOKABLE void setGradeBinding(int index, int channel, qreal depth);
    Q_INVOKABLE void addGradeKey(int index);
    Q_INVOKABLE void removeGradeKeyAt(int index);
    Q_INVOKABLE void clearGradeKeys(int index);
    Q_INVOKABLE void cycleGradeKeyInterp(int index);
    Q_INVOKABLE int  keyGradeOnMarkers(int index);

    // Playhead-varying, so kept OUT of the grade model for the same reason
    // keyedNow is kept out of `params`: rebinding that model every frame
    // rebuilds every slider.
    Q_PROPERTY(QVariantList gradeKeyedNow READ gradeKeyedNow
               NOTIFY gradeKeyStateChanged)
    Q_PROPERTY(QVariantList gradeKeyInterpNow READ gradeKeyInterpNow
               NOTIFY gradeKeyStateChanged)
    QVariantList gradeKeyedNow() const { return grade_keyed_now_; }
    QVariantList gradeKeyInterpNow() const;

    // ── project / preset (docs/contracts/project_format.md v3) ──
    // A preset is the same document without `clips`, so it can be applied over
    // whatever footage is already loaded.
    // ── per-effect layering ──
    // How node `index`'s output folds back over its own input.
    // blend: 0 normal, 1 add, 2 multiply, 3 screen, 4 difference, 5 overlay,
    // 6 subtract. mix 0 = dry, 1 = fully the effect.
    Q_INVOKABLE void setNodeBlend(int index, int blend, qreal mix);
    Q_INVOKABLE void cycleNodeBlend(int index);
    Q_INVOKABLE QStringList blendNames() const;

    // ── external control (MIDI CC / OSC) ──
    Q_INVOKABLE QStringList midiDevices() const;
    Q_INVOKABLE bool openMidi(int deviceIndex);
    // One-click first run: open the first real controller. Windows always
    // lists a "Microsoft GS Wavetable" style synth that is an OUTPUT and
    // never sends anything, so skip anything that looks like it.
    Q_INVOKABLE bool connectController();
    Q_INVOKABLE void closeMidi();
    Q_INVOKABLE bool startOsc(int port);
    Q_INVOKABLE void stopOsc();
    // Arm learn mode: the NEXT control that moves binds to this parameter of
    // the selected node. -1 disarms. Learning beats hand-entering CC numbers.
    Q_INVOKABLE void learnControl(int paramIndex);
    // The other direction, which is how hardware-first mapping works: pick a
    // control on the controller diagram, then click MAP on a parameter.
    // "" disarms. Set either way, the pair binds as soon as both are known.
    Q_INVOKABLE void armControl(const QString& key);
    Q_INVOKABLE void clearControl(int paramIndex);
    // Bind without learn mode - for --map and for project loading.
    Q_INVOKABLE void mapControl(const QString& key, int paramIndex);

    Q_PROPERTY(int learning READ learning NOTIFY controlChanged)
    Q_PROPERTY(QString lastControl READ lastControl NOTIFY controlChanged)
    Q_PROPERTY(bool midiOpen READ midiOpen NOTIFY controlChanged)
    Q_PROPERTY(bool oscOpen READ oscOpen NOTIFY controlChanged)
    // Name of the open MIDI device, "" when none. The UI matches a
    // controller layout against it.
    Q_PROPERTY(QString midiName READ midiName NOTIFY controlChanged)
    // Control armed for hardware-first mapping, "" when none.
    Q_PROPERTY(QString armedControl READ armedControl NOTIFY controlChanged)
    // Every mapping, not just the selected node's:
    // [{key, node, param, label}]. Live mode shows the whole set.
    Q_PROPERTY(QVariantList allControls READ allControls NOTIFY controlChanged)
    // Per-parameter control key, "" when unbound. Indexed like `params`.
    Q_PROPERTY(QVariantList controlMap READ controlMap NOTIFY controlChanged)
    // EVERY binding, across every effect - what controlMap cannot show because
    // it only reports the selected one. Each entry is
    // { key, node, param, effect, param_label }.
    Q_PROPERTY(QVariantList allMappings READ allMappings NOTIFY controlChanged)
    QVariantList allMappings() const;
    // Remove a binding by its control key, so a mapping can be cleared from the
    // list without first selecting the effect it belongs to.
    Q_INVOKABLE void clearMappingKey(const QString& key);
    // Live values for the selected node, so a moving knob moves its slider.
    // Separate from `params` and throttled: re-binding the params model is what
    // cost 55 fps when keyed state lived in it.
    Q_PROPERTY(QVariantList controlValues READ controlValues
               NOTIFY controlValuesChanged)

    int     learning() const { return learn_param_; }
    QString lastControl() const { return last_control_; }
    bool    midiOpen() const;
    bool    oscOpen() const;
    QVariantList controlMap() const;
    QString      midiName() const;
    QString      armedControl() const { return armed_control_; }
    QVariantList allControls() const;
    QVariantList controlValues() const;

    // ── undo / redo ──
    // Snapshot-based: every undoable edit stores the session as JSON, through
    // the same serializer the project format uses. Command objects per action
    // would be smaller but would need one implementation per edit, and any
    // missed one silently corrupts the stack; a whole-session snapshot cannot
    // miss a field. Snapshots are a few KB, so depth costs nothing.
    Q_INVOKABLE void undo();
    Q_INVOKABLE void redo();

    Q_PROPERTY(bool canUndo READ canUndo NOTIFY historyChanged)
    Q_PROPERTY(bool canRedo READ canRedo NOTIFY historyChanged)
    Q_PROPERTY(QString undoLabel READ undoLabel NOTIFY historyChanged)
    Q_PROPERTY(QString redoLabel READ redoLabel NOTIFY historyChanged)
    bool canUndo() const { return !undo_.empty(); }
    bool canRedo() const { return !redo_.empty(); }
    QString undoLabel() const { return undo_.empty() ? QString() : undo_.back().label; }
    QString redoLabel() const { return redo_.empty() ? QString() : redo_.back().label; }

    // Back to an empty session: no clips, one default effect, neutral grade.
    Q_INVOKABLE void newProject();
    // asProject=false writes a PRESET: the look only - chain, params, grade,
    // controls. No clips, no audio path, no markers, no mode, and the session
    // is not re-pointed at the file. See savePresetNamed().
    Q_INVOKABLE bool saveProject(const QUrl& url, bool asProject = true);
    Q_INVOKABLE bool loadProject(const QUrl& url);
    QString lastError() const { return last_error_; }
    Q_PROPERTY(QString lastError READ lastError NOTIFY projectChanged)
    // Retime an existing key (drag on the keyframe lane).
    Q_INVOKABLE void moveKey(int paramIndex, qreal fromTime, qreal toTime);
    int    activeClipIndex() const { return active_clip_; }
    bool   liveInput() const { return live_input_; }
    void   setLiveInput(bool on);
    qreal  liveLevel() const { return live_level_; }
    bool   hasMedia() const { return has_media_; }
    bool   hasAudio() const { return has_audio_; }
    QString mediaName() const { return media_name_; }

    // ── transport / media, called from QML (GUI thread) ──
    Q_INVOKABLE void loadMedia(const QUrl& url);
    // ── timeline / clips ──
    // Append a clip at the end of the track (start = current track duration).
    // lane < 0 means "the lowest lane with nothing on it", so a clip added
    // from the menu stacks instead of landing behind or after an existing one.
    Q_INVOKABLE void addClip(const QUrl& url, int lane = -1);
    Q_INVOKABLE void removeClip(int index);
    // Move a clip between stacked lanes (V1/V2/...); highest lane wins overlaps.
    Q_INVOKABLE void setClipLane(int index, int lane);
    // How a clip lays over the layers beneath it.
    // blend: 0 normal, 1 add, 2 multiply, 3 screen.
    Q_INVOKABLE void setClipBlend(int index, int blend, qreal opacity);
    // Placement within the frame, so a stacked clip can be moved and resized
    // rather than always covering everything.
    Q_INVOKABLE void setClipTransform(int index, qreal x, qreal y, qreal scale);
    // Rectangle of the frame the clip is allowed to paint, 0..1. This is the
    // difference between picture-in-picture (a scaled clip) and split screen
    // (two clips, each keeping its own framing, meeting at an edge).
    Q_INVOKABLE void setClipCrop(int index, qreal x, qreal y, qreal w, qreal h);

    // True while a clip is being dragged in the timeline. Republishing the clip
    // model recreates every delegate, which throws away the drag offset the
    // gesture is holding - so the poll skips it until the mouse is released.
    Q_PROPERTY(bool clipDragging READ clipDragging WRITE setClipDragging
               NOTIFY clipDraggingChanged)
    bool clipDragging() const { return clip_dragging_; }
    void setClipDragging(bool d) {
        if (clip_dragging_ == d) return;
        clip_dragging_ = d;
        emit clipDraggingChanged();
        // Catch up on whatever was skipped during the gesture.
        if (!d) pushClips_();
    }
    // Select which clip the chain rail and params panel are editing.
    // -1 = the shared chain applied to clips that have no stack of their own.
    Q_INVOKABLE void selectClip(int index);
    // Drag: move a clip's start; negative is clamped to 0.
    Q_INVOKABLE void setClipStart(int index, qreal start);
    // Copy a clip, effects and all, onto the end of its own lane. Building a
    // piece out of one loop is the common case, and re-importing the same file
    // loses whatever was set up on it.
    Q_INVOKABLE void duplicateClip(int index);

    // ---- editing ----
    // Cut a clip in two at `t` seconds. Both halves keep the effects and the
    // transform; only the trim points move, so the picture runs continuously
    // across the cut.
    Q_INVOKABLE void splitClip(int index, qreal t);
    // Clipboard. One clip, remembered until replaced - enough for the "build a
    // piece out of one loop" case this is actually for.
    Q_INVOKABLE void copyClip(int index);
    Q_INVOKABLE void pasteClip(qreal at, int lane);
    Q_PROPERTY(bool hasClipboard READ hasClipboard NOTIFY clipboardChanged)
    bool hasClipboard() const { return clipboard_valid_; }
    // Widen a clip so it covers the whole piece. Footage shorter than the track
    // already loops when rendered, so this only changes how much of the
    // timeline the clip occupies.
    Q_INVOKABLE void fillTrack(int index);
    // Edge-drag: trim within the source. out <= in means "to the end".
    Q_INVOKABLE void setClipTrim(int index, qreal in, qreal out);

    // ── audio-track clips (Phase 1) ──
    // Same editing surface as video clips, minus the per-clip chain (an audio
    // clip has no effect stack). `link` ties the clip to a video clip; the
    // linked editing gestures themselves are a later phase.
    Q_INVOKABLE void addAudioClip(const QUrl& url, int lane = -1, int link = -1);
    Q_INVOKABLE void removeAudioClip(int index);
    Q_INVOKABLE void setAudioClipStart(int index, qreal start);
    Q_INVOKABLE void setAudioClipTrim(int index, qreal in, qreal out);
    Q_INVOKABLE void setAudioClipLane(int index, int lane);
    Q_INVOKABLE void setAudioClipGain(int index, qreal gain);
    Q_INVOKABLE void splitAudioClip(int index, qreal t);
    Q_INVOKABLE void loadAudio(const QUrl& audioUrl, const QUrl& analysisUrl = {});
    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void seek(double seconds);
    // Set one uniform by index into params(). Applied on the render thread.
    Q_INVOKABLE void setParam(int index, qreal value);
    // Restore every uniform of the current effect to its manifest default.
    Q_INVOKABLE void resetParams();

    // ── Visualizer Color Styles (0=scope, 1=spectrum, 2=spectrogram, 3=vectorscope) ──
    Q_INVOKABLE QJsonObject visualizerColorStyle(int visIndex) const;
    Q_INVOKABLE void setVisualizerColorStyle(int visIndex, const QJsonObject& style);
    Q_INVOKABLE bool saveVisualizerPreset(int visIndex, const QUrl& url);
    Q_INVOKABLE bool loadVisualizerPreset(int visIndex, const QUrl& url);
    Q_PROPERTY(bool linkAllVisualizers READ linkAllVisualizers WRITE setLinkAllVisualizers NOTIFY linkAllVisualizersChanged)
    bool linkAllVisualizers() const { return link_all_visualizers_; }
    void setLinkAllVisualizers(bool link);
    Q_SIGNAL void visualizerColorStyleChanged(int visIndex);
    Q_SIGNAL void linkAllVisualizersChanged();

    // ── keyframes (per parameter of the selected node) ──
    // Record the parameter's current value at the current playhead. Keying the
    // same time twice replaces that key rather than stacking duplicates.
    Q_INVOKABLE void addKey(int paramIndex);
    // Explicit time/value, for scripted setup and for a future keyframe track
    // that drags keys around.
    Q_INVOKABLE void addKeyAt(int paramIndex, qreal time, qreal value, int interp);
    // Drop the key nearest the playhead (within a small tolerance).
    Q_INVOKABLE void removeKeyAt(int paramIndex);
    Q_INVOKABLE void clearKeys(int paramIndex);
    // Cycle linear -> ease -> step for the key nearest the playhead.
    Q_INVOKABLE void cycleKeyInterp(int paramIndex);
    // Patch bay: drive uniform `index` from an audio channel.
    // channel < 0 unbinds (static value). depth is added on top of the base
    // value, scaled by the channel level.
    Q_INVOKABLE void setBinding(int index, int channel, qreal depth);
    // Render the current chain to a file. Runs on a SEPARATE offscreen engine
    // with its own QRhi and render thread, so the live viewport keeps drawing
    // instead of freezing for the length of the export.
    // quality: 0 HIGH, 1 YOUTUBE, 2 ARCHIVE, 3 PREVIEW (rift_export_quality).
    // Resolution/fps are arguments, not constants: the menu was pinned to
    // 1920x1080, which made 4K reachable only by hand-writing a queue file.
    Q_INVOKABLE void startExport(const QUrl& outUrl, int quality,
                                 int width = 1920, int height = 1080,
                                 int fps = 60, bool noWatermark = false);
    Q_INVOKABLE void cancelExport();

    // ── render queue ──
    // Each job carries its OWN snapshot of the session, so you can queue a
    // render, keep editing, and queue another - the first still renders what
    // it was when you added it. Jobs run one at a time: each needs its own
    // QRhi + render thread, and two at once would just contend for the GPU.
    Q_INVOKABLE void enqueueExport(const QUrl& outUrl, int quality,
                                   int width = 1920, int height = 1080,
                                   int fps = 60);
    Q_INVOKABLE void startQueue();
    Q_INVOKABLE void stopQueue();          // finishes nothing new after current
    Q_INVOKABLE void removeJob(int index); // pending jobs only
    Q_INVOKABLE void clearQueue();         // pending jobs only
    Q_INVOKABLE bool loadQueue(const QUrl& url);   // batch spec, one job/line

    // [{index, name, out, quality, width, height, fps, state, percent}]
    Q_PROPERTY(QVariantList queue READ queue NOTIFY queueChanged)
    Q_PROPERTY(bool queueRunning READ queueRunning NOTIFY queueChanged)
    QVariantList queue() const { return queue_ui_; }
    bool queueRunning() const { return queue_running_; }

    // ── chain editing ──
    Q_INVOKABLE void addNode(const QString& effect);   // appended, then selected
    Q_INVOKABLE void removeNode(int index);
    Q_INVOKABLE void moveNode(int index, int delta);   // -1 earlier, +1 later

    QVariantList chain() const;
    int  selectedNode() const { return selected_; }
    void setSelectedNode(int i);

    bool   exporting() const { return exporting_; }
    int    exportPercent() const { return export_pct_; }
    QString exportStatus() const { return export_status_; }

    QVariantList params() const { return params_ui_; }
    QVariantList channelNames() const;
    QVariantList channelLevels() const { return levels_; }

signals:
    void shaderDirChanged();
    void effectChanged();
    void transportChanged();
    void statsChanged();
    void sourceChanged();
    void paramsChanged();
    void levelsChanged();
    void exportChanged();
    void clipsChanged();
    void waveformChanged();
    void markersChanged();
    void keyStateChanged();
    void gradeChanged();
    void gradeKeyStateChanged();
    void projectChanged();
    // Separate from clipsChanged on purpose: the total length changing does
    // not mean the clip MODEL changed, and binding both to one signal made
    // every x position in the timeline invalidate whenever the length moved.
    void durationChanged();
    void marksChanged();
    void clipboardChanged();
    void clipDraggingChanged();
    void presetsChanged();
    void controlChanged();
    void modeChanged();
    void queueChanged();
    void historyChanged();
    void controlValuesChanged();
    void chainChanged();
    void framedRectChanged();

protected:
    QSGNode* updatePaintNode(QSGNode*, UpdatePaintNodeData*) override;
    void     itemChange(ItemChange, const ItemChangeData&) override;
    void     geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) override;

private slots:
    void onBeforeRendering();          // render thread
    void onSceneGraphInvalidated();    // render thread

private:
    void ensureEngine_();              // render thread: build Engine once
    void pollEngine_();                // GUI thread: engine state -> properties
    // GUI thread: read <effect>.manifest.json into a node's params + UI model.
    void loadManifest_(int nodeIndex);
    void publishParams_();             // selected node's params -> params_ui_
    void refreshKeyState_();           // recompute keyed_now_, signal on change
    // Index of the key "at" the playhead, or -1. Tries the raw playhead FIRST
    // and the snapped time second, because keys arrive both ways: addKey lands
    // them on the snapped beat, while a dragged key or one from keyOnMarkers
    // can sit anywhere. Checking only one of the two made Set, Delete and the
    // keyed indicator disagree about whether a key was there.
    int keyAtPlayhead_(const std::vector<rift::Keyframe>& keys) const;
    QVariantList keyed_now_;
    QVariantList grade_ui_;                 // grade metadata + values for QML
    std::vector<rift::Param> grade_params_; // authoritative, pushed to engine
    void loadGradeManifest_();              // build both from the manifest
    void pushGrade_();
    // Mirror channel/depth/keyCount out of grade_params_ into grade_ui_. The
    // value alone is not enough once the grade can be patched and keyed.
    void publishGrade_();
    QVariantList grade_keyed_now_;
    void refreshGradeKeyState_();
    QString last_error_;

    // External control. The map is keyed by control ("cc:74", "/rift/x") so one
    // controller can drive several params and rebinding is a single assignment.
    std::unique_ptr<ControlInput> control_;
    struct ControlTarget { int node; int param; };
    QHash<QString, ControlTarget> control_map_;
    int     learn_param_ = -1;
    QString armed_control_;
    QString last_control_;
    void onControl_(const QString& key, qreal value);
    void ensureControl_();
    QTimer  control_ui_timer_;             // ~20 Hz slider echo

    struct Priv;
    std::unique_ptr<Priv> d_;
    QString shader_dir_;
    int     selected_ = 0;             // index into the chain
    bool    playing_ = false;
    double  playhead_ = 0.0;
    double  fps_ = 0.0;
    double  frame_p95_ = 0.0, frame_max_ = 0.0, gpu_ms_ = 0.0;
    bool    has_media_ = false, has_audio_ = false;
    bool    live_input_ = false;
    qreal   live_level_ = 0.0;
    QVariantList clips_ui_;            // clip track mirrored for QML
    QVariantList wave_ui_;             // audio peaks, pulled once after load
    // Engine's audio load generation that wave_ui_/markers_ were built from.
    uint32_t audio_gen_ = 0;
    QVariantList markers_ui_;          // beat times, sorted ascending
    std::vector<double> markers_;      // same list, for snapping without QVariant
    int     mode_ = 0;                 // 0 React, 1 Live
    QString project_path_;
    double  mark_in_ = 0.0, mark_out_ = 0.0;   // out <= in: no range
    rift::ClipSpec clipboard_{};
    bool           clipboard_valid_ = false;
    bool           clip_dragging_ = false;
    int     live_device_ = -1;
    QString project_title_;
    int     project_aspect_ = 0;   // 0 = 16:9
    bool    link_all_visualizers_ = false;
    QJsonObject vis_color_styles_[4];
    void    bakeAndUploadLut_(int visIndex);
    void    initVisualizerStyles_();
    bool    snap_ = true;
    // Set once the user taps/removes a marker, so the load poll stops
    // overwriting hand-placed ones with freshly detected times.
    bool    markers_edited_ = false;
    qreal   bpm_ = 0.0;
    void    publishMarkers_();         // markers_ -> markers_ui_ + notify
    qreal   track_dur_ = 0.0;
    int     active_clip_ = -1;
    int     lane_count_ = 1;
    // -1 = editing the shared chain; >= 0 = editing that clip's own stack.
    int     edited_clip_ = -1;
    // Mirror the chain being edited into the selected clip's spec. A clip's
    // chain lives in ClipSpec (plain types), so nothing about the UI's node
    // representation has to leak into this header.
    void syncChainToClip_();
    // Authoritative clip list on the UI side; pushed to the engine wholesale.
    std::vector<rift::ClipSpec> clip_specs_;
    void pushClips_();
    // Audio-track clips, same pattern: authoritative here, pushed wholesale.
    std::vector<rift::AudioClipSpec> audio_clip_specs_;
    QVariantList audio_clips_ui_;
    int audio_lane_count_ = 1;
    void pushAudioClips_();
    bool clipLayoutMoved_() const;                 // clip_specs_ -> engine + clips_ui_
    bool audioClipLayoutMoved_() const;
    QString media_name_;
    QVariantList params_ui_;           // manifest metadata + current values
    QVariantList levels_;              // live channel levels (reactivity meters)
    bool    exporting_ = false;
    int     export_pct_ = 0;
    QString export_status_;
    Q_INVOKABLE void onExportProgress(int percent, bool done);   // queued from engine thread

    // ── render queue ──
    // Everything an export needs, captured at enqueue time. Held by value: the
    // session keeps changing while the queue runs, and a job must render what
    // it was queued as.
    struct ExportJob {
        QString out, audio, analysis;
        int quality = 0, width = 1920, height = 1080, fps = 60;
        bool no_watermark = false;
        // The marked range belongs to the snapshot like everything else here.
        // Read live at job start instead, moving the marks after queueing
        // silently re-ranged every job still pending.
        double mark_in = 0.0, mark_out = 0.0;
        std::vector<rift::ClipSpec>            clips;
        std::vector<rift::AudioClipSpec>       audio_clips;
        std::vector<rift::Engine::ChainNode>   chain;
        std::vector<rift::Param>               grade;
        // The word QML shows. A parallel enum + lookup table bought nothing.
        QString state = QStringLiteral("PENDING");
        int percent = 0;
    };
    std::vector<ExportJob> jobs_;
    QVariantList queue_ui_;
    bool queue_running_ = false;
    bool cancel_requested_ = false;
    int  current_job_ = -1;

    // ── undo / redo ──
    struct Snapshot { QJsonObject state; QString label, tag; qint64 at = 0; };
    std::vector<Snapshot> undo_, redo_;
    // Guards against an undo's own restore pushing itself onto the stack.
    bool applying_history_ = false;
    static constexpr size_t kUndoDepth = 64;

    // Call BEFORE mutating. `tag` coalesces: repeats of the same tag inside
    // kCoalesceMs collapse into one step, so dragging a slider is one undo
    // rather than three hundred.
    void pushUndo_(const QString& label, const QString& tag);
    void clearRedo_();
    void applySnapshot_(const Snapshot& s);
    static constexpr qint64 kCoalesceMs = 600;

    // Serialization shared by the project format, presets and the undo stack.
    //
    // asProject is what separates a project from a preset at BOTH ends. On the
    // read side it is enforced against whatever the file actually contains, not
    // against what it ought to contain, so presets written by older builds -
    // which did carry an audio path - still apply as a look and nothing else.
    QJsonObject projectJson_(bool asProject, const QString& name) const;
    bool applyProjectJson_(const QJsonObject& root, bool asProject = true);

    ExportJob snapshotJob_(const QString& out, int quality,
                           int w, int h, int fps, bool noWatermark = false) const;
    void beginJob_(int index);      // hand one job to a fresh export engine
    void runNextJob_();             // advance, or stop when nothing is pending
    void publishQueue_();
};
