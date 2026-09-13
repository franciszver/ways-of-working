#!/usr/bin/env python3
"""build_demo.py — turn ordered screenshots into a captioned demo mp4 + gif.

Pipeline (see ../references/pipeline.md for the full rationale):

  1. Load screenshots (01-*.png ... 0N-*.png) in filename order.
  2. Overlay a caption bar on each frame (Pillow), from a captions JSON
     sidecar, onto one shared canvas size, and save each as
     frame_%04d.png in a single temp directory.
  3. Synthesize a soundtrack with the stdlib only (wave + math + array) —
     a gentle arpeggio, no numpy dependency — into the same temp directory.
  4. Build a silent mp4 straight from the frame sequence already on disk
     (imageio-ffmpeg's bundled ffmpeg), then try to mux in the soundtrack.
     If muxing fails, keep the silent mp4 rather than emit a corrupt file.
  5. Build an animated gif from the same captioned frames.

Only the final demo.mp4 and demo.gif are written to --out-dir; every
intermediate (frames, wav, silent mp4) lives in one temp directory that is
removed when the run finishes.

Exits with a clear message (not a traceback) when Pillow or
imageio-ffmpeg is missing, or when no screenshots are found.
"""
from __future__ import annotations

import argparse
import array
import json
import math
import shutil
import subprocess
import sys
import tempfile
import wave
from pathlib import Path


def require_deps():
    missing = []
    try:
        import PIL  # noqa: F401
    except ImportError:
        missing.append("Pillow (pip install Pillow)")
    try:
        import imageio_ffmpeg  # noqa: F401
    except ImportError:
        missing.append("imageio-ffmpeg (pip install imageio-ffmpeg)")
    if missing:
        print("build_demo.py requires:", file=sys.stderr)
        for m in missing:
            print(f"  - {m}", file=sys.stderr)
        raise SystemExit(1)


def load_screenshots(shots_dir: Path) -> list:
    shots = sorted(
        p for p in shots_dir.iterdir()
        if p.suffix.lower() in (".png", ".jpg", ".jpeg") and p.name[:2].isdigit()
    )
    if not shots:
        shots = sorted(
            p for p in shots_dir.iterdir()
            if p.suffix.lower() in (".png", ".jpg", ".jpeg")
        )
    if not shots:
        print(f"No screenshots found in {shots_dir}", file=sys.stderr)
        raise SystemExit(1)
    return shots


def load_captions(captions_path: Path) -> dict:
    if not captions_path.is_file():
        print(f"No captions file at {captions_path} — frames will run uncaptioned.", file=sys.stderr)
        return {}
    try:
        data = json.loads(captions_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(f"{captions_path} is not valid JSON: {e}", file=sys.stderr)
        raise SystemExit(1)
    if not isinstance(data, dict):
        print(f"{captions_path} must contain a JSON object of filename -> caption.", file=sys.stderr)
        raise SystemExit(1)
    return data


def find_font(size: int):
    from PIL import ImageFont

    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "C:\\Windows\\Fonts\\arialbd.ttf",
    ]
    for c in candidates:
        if Path(c).is_file():
            try:
                return ImageFont.truetype(c, size)
            except OSError:
                continue
    return ImageFont.load_default()


def normalize_canvas(img, target_w: int, target_h: int):
    """Letterbox img onto a target_w x target_h black canvas, centered.
    All frames must share one canvas size before encoding — ffmpeg's
    image2 sequence demuxer (and a gif's shared palette) both require it."""
    from PIL import Image

    img = img.convert("RGB")
    if img.size == (target_w, target_h):
        return img
    canvas = Image.new("RGB", (target_w, target_h), (0, 0, 0))
    x = (target_w - img.width) // 2
    y = (target_h - img.height) // 2
    canvas.paste(img, (x, y))
    return canvas


def wrap_two_lines(text: str) -> list:
    words = text.split()
    if len(words) < 2:
        return [text]
    mid = len(words) // 2
    return [" ".join(words[:mid]), " ".join(words[mid:])]


def caption_frame(img, text: str, label: str = ""):
    """Return a copy of img with a caption bar drawn across the bottom
    ~12%, centered light text that shrinks to fit. If it still doesn't fit
    at the minimum font size, wraps to two lines and grows the bar, with a
    warning to stderr — the caption is the point, so it never gets clipped
    silently."""
    from PIL import Image, ImageDraw

    img = img.convert("RGB")
    w, h = img.size

    if not text:
        return img

    margin = int(w * 0.06)
    max_avail_w = w - 2 * margin
    base_bar_h = max(int(h * 0.12), 36)
    min_font = 10

    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    lines = [text]
    bar_h = base_bar_h
    size = base_bar_h - 10
    font = find_font(size)
    while size > min_font:
        font = find_font(size)
        bbox = probe.textbbox((0, 0), text, font=font)
        if bbox[2] - bbox[0] <= max_avail_w:
            break
        size -= 2

    bbox = probe.textbbox((0, 0), text, font=font)
    if bbox[2] - bbox[0] > max_avail_w:
        lines = wrap_two_lines(text)
        size = max(min_font, base_bar_h // 2 - 10)
        font = find_font(size)
        while size > min_font:
            font = find_font(size)
            widest = max(probe.textbbox((0, 0), ln, font=font)[2] for ln in lines)
            if widest <= max_avail_w:
                break
            size -= 2
        bar_h = min(base_bar_h * 2, int(h * 0.4))
        where = f" ({label})" if label else ""
        print(f"Warning: caption too long to fit on one line at the minimum "
              f"font size{where}, wrapped to two lines: {text!r}", file=sys.stderr)

    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    draw.rectangle([(0, h - bar_h), (w, h)], fill=(0, 0, 0, 170))

    line_bbox = probe.textbbox((0, 0), "Ag", font=font)
    line_h = line_bbox[3] - line_bbox[1]
    gap = 6 if len(lines) > 1 else 0
    total_h = line_h * len(lines) + gap * (len(lines) - 1)
    y = h - bar_h + (bar_h - total_h) // 2
    for ln in lines:
        lbbox = probe.textbbox((0, 0), ln, font=font)
        tx = (w - (lbbox[2] - lbbox[0])) // 2 - lbbox[0]
        draw.text((tx, y - lbbox[1]), ln, font=font, fill=(245, 245, 245, 255))
        y += line_h + gap

    return Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")


NOTE_HZ = {
    # a calm C-G-Am-F progression, one octave, plain sine tones
    "C4": 261.63, "E4": 329.63, "G4": 392.00,
    "D4": 293.66, "B4": 493.88,
    "A4": 440.00, "F4": 349.23,
}
PROGRESSION = [
    ["C4", "E4", "G4"],
    ["G4", "B4", "D4"],
    ["A4", "C4", "E4"],
    ["F4", "A4", "C4"],
]


def synth_soundtrack(path: Path, duration_s: float, sample_rate: int = 22050) -> None:
    """Write a gentle arpeggio over `duration_s` seconds using only the
    stdlib (wave + math + array) — no numpy dependency."""
    n_samples = max(int(duration_s * sample_rate), sample_rate)
    samples = array.array("h", [0] * n_samples)

    beat_s = 0.9
    note_gap = beat_s / 3.0
    t = 0.0
    chord_i = 0
    while t < duration_s:
        chord = PROGRESSION[chord_i % len(PROGRESSION)]
        for note in chord:
            freq = NOTE_HZ[note]
            start = t
            end = min(t + note_gap * 2, duration_s)  # notes overlap slightly
            n_start = int(start * sample_rate)
            n_end = min(int(end * sample_rate), n_samples)
            note_len = max(n_end - n_start, 1)
            attack = max(int(note_len * 0.1), 1)
            decay = max(int(note_len * 0.4), 1)
            for i in range(note_len):
                idx = n_start + i
                if idx >= n_samples:
                    break
                if i < attack:
                    env = i / attack
                elif i > note_len - decay:
                    env = max(0.0, (note_len - i) / decay)
                else:
                    env = 1.0
                val = math.sin(2 * math.pi * freq * (i / sample_rate)) * env * 0.15
                samples[idx] += int(max(-32768, min(32767, val * 32767)))
            t += note_gap
        chord_i += 1

    # fade in/out sized to the clip
    fade_n = min(int(sample_rate * 1.0), n_samples // 4)
    for i in range(fade_n):
        f = i / fade_n
        samples[i] = int(samples[i] * f)
        samples[n_samples - 1 - i] = int(samples[n_samples - 1 - i] * f)

    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(samples.tobytes())


def build_silent_video(frames_dir: Path, out_path: Path, hold_s: float, fps: int, ffmpeg_exe: str) -> None:
    """frames_dir must already contain frame_0000.png, frame_0001.png, ...
    — captioned frames are saved directly in that layout so this shells
    out to ffmpeg with no extra decode/re-encode round trip."""
    cmd = [
        ffmpeg_exe, "-y",
        "-framerate", str(1.0 / hold_s),
        "-i", str(frames_dir / "frame_%04d.png"),
        "-r", str(fps),
        "-pix_fmt", "yuv420p",
        "-c:v", "libx264",
        str(out_path),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        raise SystemExit(f"ffmpeg failed to build the silent video: {out_path}")


def mux_audio(video_path: Path, audio_path: Path, out_path: Path, ffmpeg_exe: str) -> bool:
    cmd = [
        ffmpeg_exe, "-y",
        "-i", str(video_path),
        "-i", str(audio_path),
        "-c:v", "copy", "-c:a", "aac", "-shortest",
        str(out_path),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode == 0 and out_path.is_file()


def build_gif(frame_imgs: list, out_path: Path, hold_s: float, max_mb: float) -> None:
    frames = [f.convert("P", palette=1) for f in frame_imgs]  # 1 = Image.ADAPTIVE
    frames[0].save(
        out_path, save_all=True, append_images=frames[1:],
        duration=int(hold_s * 1000), loop=0, optimize=True,
    )
    # crude size cap: shrink until under max_mb or too small to bother
    while out_path.stat().st_size > max_mb * 1024 * 1024 and frames[0].width > 320:
        frames = [f.resize((int(f.width * 0.85), int(f.height * 0.85))) for f in frames]
        frames[0].save(
            out_path, save_all=True, append_images=frames[1:],
            duration=int(hold_s * 1000), loop=0, optimize=True,
        )
    size_mb = out_path.stat().st_size / 1024 / 1024
    if size_mb > max_mb:
        print(f"Warning: {out_path} is {size_mb:.2f} MB, over the {max_mb} MB "
              f"target even at {frames[0].width}px wide.", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build a captioned demo mp4 + gif from ordered screenshots.",
    )
    parser.add_argument("--screenshots-dir", required=True, type=Path,
                         help="Directory of 01-*.png .. 0N-*.png screenshots, in play order.")
    parser.add_argument("--captions", type=Path, default=None,
                         help="JSON file mapping screenshot filename -> caption text "
                              "(default: demo_captions.json inside --screenshots-dir).")
    parser.add_argument("--out-dir", type=Path, default=Path("."),
                         help="Directory to write demo.mp4 and demo.gif into (default: cwd). "
                              "Only these two files are written here.")
    parser.add_argument("--hold", type=float, default=2.5,
                         help="Seconds each frame is held on screen (default: 2.5).")
    parser.add_argument("--fps", type=int, default=24,
                         help="Output video frame rate (default: 24).")
    parser.add_argument("--max-gif-mb", type=float, default=2.0,
                         help="Target maximum gif size in MB (default: 2.0).")
    args = parser.parse_args()

    require_deps()
    import imageio_ffmpeg
    from PIL import Image

    if not args.screenshots_dir.is_dir():
        print(f"--screenshots-dir does not exist: {args.screenshots_dir}", file=sys.stderr)
        return 1
    args.out_dir.mkdir(parents=True, exist_ok=True)

    captions_path = args.captions or (args.screenshots_dir / "demo_captions.json")
    shots = load_screenshots(args.screenshots_dir)
    captions = load_captions(captions_path)
    ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()

    print(f"Normalizing {len(shots)} frame(s) to one canvas size...")
    sizes = []
    for shot in shots:
        with Image.open(shot) as im:
            sizes.append(im.size)
    target_w = max(s[0] for s in sizes)
    target_h = max(s[1] for s in sizes)
    target_w += target_w % 2  # even dimensions: libx264's yuv420p rejects odd ones
    target_h += target_h % 2

    with tempfile.TemporaryDirectory(prefix="demo-build-") as tmp_str:
        tmp = Path(tmp_str)

        print(f"Captioning {len(shots)} frame(s)...")
        captioned_imgs = []
        for i, shot in enumerate(shots):
            text = captions.get(shot.name, "")
            with Image.open(shot) as im:
                normalized = normalize_canvas(im, target_w, target_h)
            captioned = caption_frame(normalized, text, label=shot.name)
            captioned_imgs.append(captioned)
            captioned.save(tmp / f"frame_{i:04d}.png")
            print(f"  {shot.name}: {text!r}" if text else f"  {shot.name}: (no caption)")

        silent_mp4 = tmp / "demo-silent.mp4"
        final_mp4 = args.out_dir / "demo.mp4"
        gif_path = args.out_dir / "demo.gif"

        print("Building silent video...")
        build_silent_video(tmp, silent_mp4, args.hold, args.fps, ffmpeg_exe)

        duration_s = len(shots) * args.hold
        wav_path = tmp / "soundtrack.wav"
        print(f"Synthesizing {duration_s:.1f}s soundtrack (stdlib only)...")
        synth_soundtrack(wav_path, duration_s)
        print("Muxing audio into video...")
        has_audio = mux_audio(silent_mp4, wav_path, final_mp4, ffmpeg_exe)
        if not has_audio:
            print("Audio mux failed — keeping the silent mp4.", file=sys.stderr)
            shutil.copyfile(silent_mp4, final_mp4)

        print("Building gif...")
        build_gif(captioned_imgs, gif_path, args.hold, args.max_gif_mb)

        # everything in tmp (frames, wav, silent mp4) is removed on exit;
        # only final_mp4 and gif_path, already in --out-dir, survive.
        mp4_size = final_mp4.stat().st_size / 1024 / 1024
        gif_size = gif_path.stat().st_size / 1024 / 1024
        print("\nDone.")
        print(f"  mp4: {final_mp4} ({mp4_size:.2f} MB, audio: {has_audio})")
        print(f"  gif: {gif_path} ({gif_size:.2f} MB)")
        print("Verify by looking: open one captioned frame, confirm audio with "
              "`ffmpeg -i <mp4>` (look for an Audio: stream line), and check the "
              "gif animates with the expected frame count before publishing.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
