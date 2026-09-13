---
name: demo-video
description: Turns a running app into a captioned demo video (mp4 + gif with music) and publishes it — captures ordered screenshots, overlays explanatory captions, synthesizes a soundtrack, commits the gif into the README. Use when asked to make a demo video/gif of an application, a walkthrough recording, or a README hero animation.
---

# Demo Video

A demo video is an argument that the product works, made to someone who will not run it. The whole job is to compress a real session into a few captioned frames that a viewer understands in ten seconds — and to publish it where it's seen (the README), not buried as an attachment.

**Prerequisites:** Python 3.9+, Pillow, imageio-ffmpeg, a running app to screenshot, and a README to publish into. Run `scripts/build_demo.py --help` for the pipeline's options; step-by-step mechanics live in `references/pipeline.md`.

## 1. Capture judgment

Capture the **running** app, not an empty or logged-out shell — a cold-started, unseeded, or half-rendered screen is worse than no demo. See `references/pipeline.md` §1 for the warm-up and completion-marker details.

## 2. Caption judgment

Captions are the point — a frame without one is a mystery. Write them for someone who will never run the app: what is happening and why it matters, not a UI label restated. Keep them short enough to read in the hold time per frame.

## 3. Verify by looking, not by trusting

The build "succeeding" proves nothing about what a human sees. Before shipping: open one captioned frame and confirm the caption is legible and correct; probe the mp4 for a real audio stream (`ffmpeg -i` stderr shows `Audio:`); confirm the gif has the expected frame count and is animated. A silent mp4 or an unreadable caption that ships is the same as no demo.

## 4. Publish judgment

- **Commit the gif** to a tracked path (e.g. `docs/assets/demo.gif`), keep it under ~2 MB, and embed it near the top of the README: `![<app> demo](docs/assets/demo.gif)` with a one-line caption. GitHub renders it inline — that's the whole reason to prefer gif for the README.
- **Gitignore the mp4 and the raw frames** — the mp4 is large and regenerates; deliver it as a file for review or attach it to a Release. Committing large, regenerating binaries bloats the repo permanently.

## Anti-patterns

- Capturing an empty, logged-out, or zero-data state and calling it a demo.
- Captions too small, too long, or too low-contrast to read at a glance.
- Committing the mp4 to the repo instead of the gif.
- `sleep(N)` instead of waiting for a completion marker — ships a half-rendered frame.
