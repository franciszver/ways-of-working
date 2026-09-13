---
name: demo-video
description: Turns a running app into a captioned demo video (mp4 + gif with music) and publishes it — captures ordered screenshots, overlays explanatory captions, synthesizes a soundtrack, commits the gif into the README. Use when asked to make a demo video/gif of an application, a walkthrough recording, or a README hero animation.
---

<!-- local: derived-from: skills/demo-video/SKILL.md@e65bf5e17241 -->

# Demo Video

You are producing a captioned demo of a running app and publishing it. Token usage is not a concern — verify every output from disk. A demo that ships broken (empty state, unreadable caption, silent mp4, giant committed binary) is worse than none.

## Fill in first
- APP URL (running). Warm it: curl it 2x before capturing (free tiers cold-start).
- LOGIN: read creds from an env var / `.env` key BY NAME — never paste the secret.
- FLOW: 5–8 ordered screens, each with a one-line caption saying what it demonstrates.

## Step 1 — CAPTURE
Screenshot each screen in order → `01-*.png … 0N-*.png` (filename order = play order) into a GITIGNORED dir. Log in with the env creds. On async/AI screens, wait for the FINISHED content (a completion marker), not a fixed sleep. Seed real demo data if the account is empty — no dashboards of zeroes.

## Step 2 — BUILD (`scripts/build_demo_media.py`, reads sorted PNGs)
- Tools that are actually present: `Pillow` for images/gif; `imageio-ffmpeg` for mp4 (it BUNDLES ffmpeg — `imageio_ffmpeg.get_ffmpeg_exe()`; NO system ffmpeg). Synthesize audio with STDLIB `wave`+`math` only — do NOT assume numpy.
- Captions: semi-transparent dark bar (~12% height) at the bottom of each frame, centered light text auto-shrunk to fit; TrueType font if available else `ImageFont.load_default()` (never crash). Same captions on mp4 AND gif. Normalize to one canvas size; handle odd dimensions. Captions in a `demo_captions.json` sidecar.
- Music (mp4 only; gif silent): gentle low-volume arpeggio, calm progression (e.g. C–G–Am–F), sine + attack/decay ramps (no clicks), amplitude with headroom + clamp, fade in/out, sized to the video. Mux via bundled ffmpeg: `-i video -i wav -c:v copy -c:a aac -shortest`. On failure, KEEP the silent mp4. Temp files in a TemporaryDirectory; close all handles before cleanup (Windows locks files).
- Output demo.mp4 + demo.gif (~3s/frame, gif width ~900).

## Step 3 — VERIFY (don't skip)
OPEN one captioned frame and confirm the caption is legible/correct. Probe the mp4 for an audio stream (`ffmpeg -i`, look for "Audio:"). Confirm the gif has the right frame count and is animated.

## Step 4 — PUBLISH + COMMIT
- Commit the gif to a TRACKED path (`docs/assets/demo.gif`, <~2 MB). Embed near the top of README: `![demo](docs/assets/demo.gif)`.
- GITIGNORE the mp4 + raw frames (mp4 is large, regenerates — hand it over as a file / attach to a Release).
- No secrets committed. Scope the formatter to the files you changed. Red-first tests for the pipeline (caption changes a frame; mp4 has audio with music on / none off; odd dims don't crash); gate tooling tests with `pytest.importorskip`. Branch → PR → review → CI → merge.
