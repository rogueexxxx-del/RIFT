"""Check repeatable Engine exports using disposable moving media and audio."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", required=True, type=Path)
    parser.add_argument("--ffmpeg", required=True, type=Path)
    args = parser.parse_args()
    exe, ffmpeg = args.exe.resolve(), args.ffmpeg.resolve()
    ffprobe = ffmpeg.with_name("ffprobe" + ffmpeg.suffix)
    env = os.environ.copy()
    for key in list(env):
        if key.startswith(("QT_", "QML_", "QML2_", "RIFT_UI_TEST")):
            env.pop(key)
    env["PATH"] = os.pathsep.join((str(Path(env["SYSTEMROOT"]) / "System32"), env["SYSTEMROOT"]))

    def run(command):
        result = subprocess.run([str(x) for x in command], env=env,
                                capture_output=True, text=True, timeout=180)
        if result.returncode:
            raise RuntimeError(f"{command[0]} exited {result.returncode}: {result.stderr[-4000:]}")
        return result.stdout

    with tempfile.TemporaryDirectory(prefix="rift-export-parity-") as directory:
        work = Path(directory)
        media, audio = work / "source.mp4", work / "source.wav"
        run([ffmpeg, "-v", "error", "-f", "lavfi", "-i",
             "testsrc2=size=320x180:rate=30:duration=5", "-c:v", "mpeg4", "-q:v", "2", media])
        run([ffmpeg, "-v", "error", "-f", "lavfi", "-i",
             "sine=frequency=443:duration=5", "-c:a", "pcm_s16le", audio])
        reference = []
        for index in range(2):
            output = work / f"export-{index}.mp4"
            run([exe, "--media", media, "--audio", audio, "--chain", "ascii,prism_split",
                 "--export-width", "320", "--export-height", "180", "--export", output])
            streams = json.loads(run([ffprobe, "-v", "error", "-count_frames",
                "-show_entries", "stream=codec_type,width,height,nb_read_frames,duration",
                "-of", "json", output]))["streams"]
            video = next(stream for stream in streams if stream["codec_type"] == "video")
            assert (video["width"], video["height"]) == (320, 180), video
            # CLI export truncates the project duration to whole 60 fps frames.
            assert 299 <= int(video["nb_read_frames"]) <= 300, video
            assert abs(float(video["duration"]) - 5) < 1 / 60 + 0.001, video
            sound = next(stream for stream in streams if stream["codec_type"] == "audio")
            assert abs(float(sound["duration"]) - 5) < 0.05, sound
            hashes = run([ffmpeg, "-v", "error", "-i", output, "-map", "0:v:0",
                          "-pix_fmt", "rgba", "-f", "framemd5", "-"])
            frames = [line for line in hashes.splitlines() if line and not line.startswith("#")]
            assert len(frames) == int(video["nb_read_frames"])
            assert len({line.rsplit(",", 1)[-1] for line in frames}) > 1, "Export must contain moving imagery"
            if reference:
                assert frames == reference, "Repeated exports differ frame by frame"
            reference = frames
        print(f"PASS: two {len(reference)}-frame Engine exports match frame by frame; moving video and 5s audio verified")


if __name__ == "__main__":
    main()
