# Demo pipeline — step details

The mechanics behind `scripts/build_demo.py`, in the order the script runs
them. Read this when the pipeline needs a manual step or the script needs a
change; the skill body keeps only the judgment calls.

## 1. Capture

Screenshot the **running** app, in order, one PNG per beat, named
`01-*.png … 0N-*.png` (filename order = play order) into a **gitignored**
scratch dir.

- **Warm it up.** Free-tier hosts cold-start — curl the health endpoint /
  homepage a couple times before the first shot, or frame 1 is a spinner.
- **Wait for real content, not a fixed sleep.** Log in with credentials read
  from an **env var / `.env` key by name** (never paste the secret). On
  async or AI-generated screens, wait for the finished content to appear (a
  completion marker), not `sleep(3)` — a half-rendered answer is worse than
  none. Seed real demo data first if the account is empty; a dashboard of
  zeroes sells nothing.

If a browser can't reach the app, degrade to a manual screenshot checklist
with the same filenames — the build steps below are identical either way.

## 2. Normalize and caption

All frames are letterboxed onto one shared canvas size (the max width and
height across the set, rounded up to even) before anything else — a mixed
set of screenshot sizes otherwise breaks ffmpeg's image2 sequence demuxer
and produces a gif with a wrong or inconsistent palette.

Captions are drawn with a semi-transparent dark bar across the bottom ~12%
of each frame, centered light text that auto-shrinks to fit, loading a
TrueType font if one exists and falling back to `ImageFont.load_default()`
without crashing. Captions are applied identically to both the mp4 and the
gif so they match, and live in a `demo_captions.json` sidecar (filename ->
caption text) so text edits don't touch code.

## 3. Soundtrack — stdlib only

Synthesize with `wave` + `math` + `array` — a gentle, low-volume arpeggio
over a calm progression (C–G–Am–F), sine waves with per-note attack/decay
ramps so there are no clicks, amplitude with headroom, a defensive clamp on
the 16-bit packing, and a short fade in/out sized to the video length. Do
**not** reach for numpy; it is frequently absent on a fresh machine.

## 4. Video and mux

`imageio-ffmpeg` bundles an ffmpeg binary — get it via
`imageio_ffmpeg.get_ffmpeg_exe()` and shell out to it. Build the silent mp4
from the frame sequence first, then mux the wav in with
`-i video -i wav -c:v copy -c:a aac -shortest`. If muxing fails, keep the
silent mp4 rather than emit a corrupt one. Keep temp files in a
`TemporaryDirectory` and close every reader/writer handle before cleanup
(Windows locks open files).

## 5. Gif

Build the gif from the same normalized, captioned frames Pillow already
produced, so mp4 and gif never drift. If the result is over the size
target, shrink the frame dimensions and re-encode rather than dropping
frames — dropping frames changes the story being told.

## 6. Ship it like any change

Branch, red-first tests for the pipeline code (caption overlay produces a
visibly different frame; the mp4 has an audio stream with music on and none
with it off; mismatched-size frames don't crash — all hermetic, handles
closed before tmp cleanup), gate the tooling tests with
`pytest.importorskip` so CI without Pillow/imageio-ffmpeg skips instead of
erroring at collection, scope the formatter to the files you changed, then
PR → review → CI → merge. Report the caption list, the audio-stream
confirmation, the committed gif path + size, and the PR link; deliver the
mp4 as a file.
