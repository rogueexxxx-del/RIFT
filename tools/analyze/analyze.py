"""
Offline analyzer - writes the .analysis blob the C++ runtime memory-maps.
Reuses the prototype AudioEngine._analyze() so stem accuracy is identical.

Usage:
    python analyze.py INPUT_AUDIO OUTPUT.analysis
Blob format: docs/contracts/analysis_blob.md (v1)
"""
import sys, os, struct
import numpy as np

# import the prototype engine unchanged
_PROTO = os.path.join(os.path.dirname(__file__), "..", "..", "..", "RIFT")
sys.path.insert(0, os.path.abspath(_PROTO))
from audio_engine import AudioEngine  # noqa: E402

MAGIC = b"RIFTANLZ"
VERSION = 1
# plane order MUST match rift_channel enum / blob contract
CHANNELS = [
    ("bass", 0), ("melody", 0), ("highs", 0), ("drums", 0),
    ("transient", 1), ("bpm", 0), ("centroid", 0), ("time", 2),
    ("kick", 1), ("snare", 1),
]


def analyze(audio_path: str) -> dict:
    e = AudioEngine(fps=60)
    e.load(audio_path)  # runs _demucs_separate + _analyze
    n = e.total_frames
    bpm = float(np.clip(e._bpm_norm, 0, 1)) * 200.0

    def arr(a):
        return (np.resize(a, n) if a is not None
                else np.zeros(n, np.float32)).astype(np.float32)

    planes = {
        "bass": arr(e._bass), "melody": arr(e._melody), "highs": arr(e._highs),
        "drums": arr(e._drums), "transient": arr(e._transient),
        "bpm": np.full(n, e._bpm_norm, np.float32),
        "centroid": arr(e._centroid), "time": np.zeros(n, np.float32),
        "kick": arr(e._kick), "snare": arr(e._snare),
    }
    return dict(sr=e._sr, hop=e._hop, fps=e.fps, n=n, bpm=bpm, planes=planes)


def write_blob(meta: dict, out_path: str):
    n, C = meta["n"], len(CHANNELS)
    with open(out_path, "wb") as f:
        # header (64 bytes)
        f.write(MAGIC)
        f.write(struct.pack("<II", VERSION, 0))                  # version, flags
        f.write(struct.pack("<IIII", meta["sr"], meta["hop"], meta["fps"], n))
        f.write(struct.pack("<I", C))
        f.write(struct.pack("<f", meta["bpm"]))
        f.write(struct.pack("<6I", 0, 0, 0, 0, 0, 0))            # reserved -> 64B header
        # channel table (C * 16 bytes)
        for name, kind in CHANNELS:
            nm = name.encode("ascii")[:12].ljust(12, b"\0")
            f.write(nm)
            f.write(struct.pack("<I", kind))
        # data planes (C * n float32, plane-major)
        for name, _ in CHANNELS:
            f.write(meta["planes"][name].astype("<f4").tobytes())


def read_blob(path: str) -> dict:
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == MAGIC, "bad magic"
    version, flags = struct.unpack_from("<II", data, 8)
    sr, hop, fps, n = struct.unpack_from("<IIII", data, 16)
    C = struct.unpack_from("<I", data, 32)[0]
    bpm = struct.unpack_from("<f", data, 36)[0]
    off = 64
    names = []
    for _ in range(C):
        nm = data[off:off + 12].rstrip(b"\0").decode("ascii")
        kind = struct.unpack_from("<I", data, off + 12)[0]
        names.append((nm, kind)); off += 16
    planes = {}
    for nm, _ in names:
        planes[nm] = np.frombuffer(data, "<f4", n, off).copy(); off += n * 4
    return dict(version=version, sr=sr, hop=hop, fps=fps, n=n, C=C,
                bpm=bpm, names=names, planes=planes)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("usage: analyze.py INPUT_AUDIO OUTPUT.analysis"); sys.exit(1)
    meta = analyze(sys.argv[1])
    write_blob(meta, sys.argv[2])
    print(f"[analyze] {meta['n']} frames, {len(CHANNELS)} channels, "
          f"bpm {meta['bpm']:.1f} -> {sys.argv[2]} "
          f"({os.path.getsize(sys.argv[2])} bytes)")
