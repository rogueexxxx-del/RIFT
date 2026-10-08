# `.rift` Project Format Contract  (v5)

Full session state. Superset of the prototype `.rift` (core/project.py v1) -
adds a node-graph representation while staying backward compatible with the
linear chain. JSON + external asset references (assets NOT embedded).

**v3 adds** what the C++/QML app gained after the port: a multi-clip timeline
(lanes, trim, blend, transform, per-clip effect stacks), per-parameter
keyframes, and the master colour grade. A preset and a project are the same
document - a "preset" is simply one saved without `clips`, so it can be applied
over whatever footage is already loaded.

**v4 adds** `controls` (MIDI/OSC mapping) and user `markers`.

**v5 adds** `audio_clips` (timeline audio tracks + real-time mixing) and `link` on clips.

## v5 top level
```json
{
  "format": "rift-project",
  "version": 5,
  "name": "my-visual",
  "aspect": 0,                        // 0: 16:9, 1: 1:1, 2: 4:3, 3: 9:16, 4: 21:9

  "analysis_path": "cached.analysis", // optional precomputed blob for single-clip mix

  "grade": [ <param>, ... ],          // color_grade.layout.json order
  "controls": [                       // v4: external controller bindings
    { "key": "cc:74",    "node": 0, "param": 1 },
    { "key": "/rift/x",  "node": 0, "param": 0 }
  ],
  "markers": [ 0.51, 1.02, 1.51 ],    // v4: beat times, seconds
  "chain": [                          // shared chain, applied to un-stacked clips
    { "shader": "ascii", "params": [ <param>, ... ], "blend": 4, "mix": 0.5 }
  ],
  "clips": [                          // omit entirely for a preset
    {
      "path": "clip.mp4",
      "start": 0.0, "in": 0.0, "out": 0.0, "lane": 0,
      "link": 0,                      // v5: linked A/V clip id (-1 or omitted = independent)
      "blend": 0, "opacity": 1.0,
      "posX": 0.0, "posY": 0.0, "scale": 1.0,
      "chain": [ { "shader": "glitch", "params": [ <param>, ... ] } ]
    }
  ],
  "audio_clips": [                    // v5: omit entirely for a preset
    {
      "path": "soundtrack.wav",
      "name": "soundtrack.wav",
      "start": 0.0, "in": 0.0, "out": 0.0, "lane": 0,
      "gain": 1.0, "link": 0
    }
  ]
}
```

`start: -1` means "append after the previous clip in this lane" - the timeline
resolves it once the source opens, so a saved project keeps that intent instead
of freezing a position computed from a not-yet-known duration.

A chain entry's `blend`/`mix` decide how that effect's OUTPUT folds back over
its own INPUT - distinct from a clip's `blend`/`opacity`, which decide how a
lane sits over the lane beneath. Both use the same mode numbering:
`0 normal, 1 add, 2 multiply, 3 screen, 4 difference, 5 overlay, 6 subtract`.

`markers` is written ONLY once markers have been hand-edited. Detected beats are
reproducible from the audio, so freezing them into the project would stop a
later re-detect (with different sensitivity, or a better analysis blob) from
ever reaching an existing project. Absent = detect on load.

`controls[].key` is `"cc:<n>"` for a MIDI Control Change or the literal OSC
address for OSC. Both sources deliver 0..1, scaled on arrival into the target
parameter's manifest range. Omitted entirely when nothing is mapped.

## v4 param entry
Positional (matches the shader's layout order), and carries automation:
```json
{
  "value": 100.0,
  "channel": 3,            // rift_channel index, -1 = static
  "depth": 80.0, "curve": "lin",
  "attack": 0.0, "release": 0.0,
  "in_lo": 0.0, "in_hi": 1.0, "invert": false,
  "keys": [ { "t": 0.0, "v": 20.0, "i": 0 } ]   // i: 0 linear, 1 ease, 2 step
}
```
Ranges (`min`/`max`/`step`) are NOT stored - they come from the shader manifest
on load, so tweaking a manifest updates existing projects instead of being
overridden by stale copies.

## Top level
```json
{
  "format": "rift-project",
  "version": 2,
  "name": "my-visual",

  "media_path": "abs/or/relative.mp4",
  "audio_path": "abs/or/relative.wav",
  "analysis_path": "cached.analysis",     // optional precomputed blob
  "ascii_text": "RIFT",
  "loop": true,
  "grid_mode": "1x1",

  "palette": { "idx": 0, "active": false,
               "bg":[r,g,b], "fg1":[r,g,b], "fg2":[r,g,b] },

  "graph": {                               // v2 node graph
    "nodes": [
      {"id":"src",  "type":"source"},
      {"id":"gen",  "type":"effect", "shader":"ascii",   "params":{...}},
      {"id":"fx1",  "type":"effect", "shader":"halftone","params":{...}},
      {"id":"out",  "type":"output", "params":{...}}     // master post_fx
    ],
    "edges": [["src","gen"],["gen","fx1"],["fx1","out"]]
  }
}
```

## Param entry (per uniform) - matches Mod v2
```json
"ht_scale": {
  "value": 9.0, "source": "drums", "mod_amount": 6.0,
  "attack": 0.0, "release": 0.0, "curve": "lin",
  "in_lo": 0.0, "in_hi": 1.0, "invert": false
}
```

## Asset resolution (same as prototype)
1. absolute `*_path` if it exists
2. else basename next to the `.rift`
3. else report missing → UI prompts re-import

## Backward compatibility
- v1 `.rift` (linear `chain` list + `effects` + `post_fx`) loads: a migrator
  synthesizes a linear `graph` (source→generator→chain...→output).
- v2 `.rift` loads: `graph.nodes` of type `effect` become the shared `chain`,
  `media_path` becomes a single clip, and the grade comes up neutral.
- v3 loads unchanged; `controls` is simply absent, meaning nothing is mapped.
- v4 loads: `audio_path` is migrated to one `audio_clips` entry on lane 0 (A1).
  If `analysis_path` exists, single-clip blob reactivity is preserved.
- v5 introduces `audio_clips` and clip `link`. Saving always writes v5.
- Loader migrates in memory; save always writes current version.

## Versioning
Integer `version`. Unknown keys ignored. Newer-than-engine files load
best-effort with a warning (matches prototype behavior).
