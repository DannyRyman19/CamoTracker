#!/usr/bin/env python3
"""
assemble.py - cut the recorded takes into captioned segments and join them
into the App Store preview.

    /usr/bin/python3 Tools/preview/assemble.py <workDir> <out.mp4>

<workDir> holds takes/<take>.mov (from make.sh) and plates/ (from
plate.swift). Output is 886x1920, 30 fps, H.264 High, with a silent stereo
AAC track: the App Store 6.9"/6.7" app preview spec. The recording fills the
frame edge to edge with the caption laid over it; App Review rejects a
preview that puts framing around the app.
"""
import subprocess
import sys
from pathlib import Path

FPS = 30
XFADE = 0.5   # seconds each caption / take change crossfades over

# (take, start, end, caption) in recording time. make.sh touches the go file
# one second after the recording starts, so a harness sleep of N seconds in
# Sources/ContentView.swift (SS_DEMO) lands at N + 1.0 here. Consecutive
# segments of the same take overlap by XFADE, so across a caption change the
# footage is continuous and only the headline crossfades.
SEGMENTS = [
    ("grind",   1.00,  4.00, "challenges"),  # the weapon's camo list, settled
    ("grind",   3.50,  7.20, "tick"),        # 3.5 the bar fills to 10/10
    ("grind",   6.70, 11.00, "gold"),        # 6.5 last camo ticked, Gold banner
    ("suggest", 0.50,  4.30, "next"),        # the Suggested card
    ("stats",   0.50,  4.50, "stats"),
]


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def main(work: Path, out: Path) -> None:
    parts: list[tuple[Path, int]] = []
    for i, (take, start, end, caption) in enumerate(SEGMENTS):
        frames = round((end - start) * FPS)
        part = work / f"seg{i}.mp4"
        # simctl records only when the screen changes, so a still stretch (a
        # whole static take) can be one frame. No input seek, then: fps fills
        # the gaps, tpad holds the last frame, trim cuts in the filter graph
        # where every timestamp is guaranteed to have a frame.
        run(["ffmpeg", "-nostdin", "-y",
             "-i", str(work / f"takes/{take}.mov"),
             "-loop", "1", "-i", str(work / f"plates/{caption}.png"),
             "-filter_complex",
             f"[0:v]fps={FPS},tpad=stop_mode=clone:stop_duration=30,"
             f"trim=start={start}:duration={frames / FPS},setpts=PTS-STARTPTS,"
             # 1320x2868 scales to 886x1926; the crop takes 3 px off each end.
             f"scale=886:1926:flags=lanczos,crop=886:1920[v];"
             f"[v][1:v]overlay=0:0:shortest=1,format=yuv420p[out]",
             "-map", "[out]", "-frames:v", str(frames),
             "-c:v", "libx264", "-preset", "slow", "-crf", "12", str(part)])
        parts.append((part, frames))

    # Chain the crossfades: each xfade's offset is where the next part starts
    # on the joined timeline so far.
    inputs: list[str] = []
    for part, _ in parts:
        inputs += ["-i", str(part)]
    chain, label, length = [], "[0:v]", parts[0][1] / FPS
    for i, (_, frames) in enumerate(parts[1:], start=1):
        offset = length - XFADE
        nxt = f"[x{i}]"
        chain.append(f"{label}[{i}:v]xfade=transition=fade:duration={XFADE}:offset={offset:.4f}{nxt}")
        label, length = nxt, offset + frames / FPS
    chain.append(f"{label}format=yuv420p[out]")

    run(["ffmpeg", "-y", *inputs,
         "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
         "-filter_complex", ";".join(chain),
         "-map", "[out]", "-map", f"{len(parts)}:a",
         "-c:v", "libx264", "-profile:v", "high", "-level", "4.0", "-pix_fmt", "yuv420p",
         "-r", str(FPS), "-b:v", "10M", "-maxrate", "12M", "-bufsize", "24M",
         "-c:a", "aac", "-b:a", "256k", "-t", f"{length:.4f}",
         "-movflags", "+faststart", str(out)])
    for part, _ in parts:
        part.unlink()
    print(f"wrote {out}  {length:.2f}s")
    if not 15 <= length <= 30:
        sys.exit(f"App Store previews must run 15-30s; this one is {length:.2f}s")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(Path(sys.argv[1]), Path(sys.argv[2]))
