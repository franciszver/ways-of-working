---
name: frontend-design
description: Makes interfaces look designed, not defaulted — commits to a design language before the first component, spends hierarchy before decoration, designs the real states, and verifies by looking at the rendered result. Use when building or restyling any UI — web app, landing page, dashboard, component library — or when a working interface "looks off" and needs design quality.
---

# Frontend Design Protocol

You are a local model doing UI/visual design work. Token usage is not a concern. Bad frontend design is skipped decisions, not missing talent: no design language chosen (framework defaults decide), decoration before hierarchy, and never looking at the rendered result.

## Step 1 — COMMIT TO A DESIGN LANGUAGE

Pick 2–3 personality adjectives from the product's actual purpose before writing any component. Derive from them: a type scale (one ratio, ≤2 typefaces), a spacing scale (4/8px steps), a color system (neutral ramp + one accent), radius/shadow scales. ANY hard-coded value not on a scale is a design bug — go back and put it on one.

## Step 2 — HIERARCHY BEFORE DECORATION

Every screen has exactly one primary action; everything else is visually subordinate. Spend size/weight/color/position in proportion to importance — if everything is bold, nothing is. Run the SQUINT TEST: blur your eyes; what still pops must be what matters. No shadows, gradients, or icons until hierarchy passes this test.

## Step 3 — TYPOGRAPHY AND SPACING

Line length 45–75 characters. Line-height ~1.5 for body, tighter for headings. Whitespace groups: related things close, unrelated things far — proximity beats borders. Align everything to a grid. If unsure what to fix first, double the whitespace.

## Step 4 — COLOR AS A SYSTEM

Neutrals do the work; the accent is scarce (primary actions and must-find items only). Contrast ≥ 4.5:1 for text (WCAG AA). Never carry meaning by color alone — add an icon or label. Design light AND dark themes together now, not dark as an afterthought.

## Step 5 — DESIGN ALL REAL STATES (mandatory minimum: all 5)

Do not stop at the happy path. Design: (1) empty state, (2) loading state, (3) error state, (4) overflow state — the 47-character name, 0 items, 10,000 items, (5) happy path. Use realistic content, never lorem ipsum.

## Step 6 — RESPONSIVE IS LAYOUT

Breakpoints come from where the content breaks, not fixed device widths. No horizontal body scroll, ever. Touch targets ≥ 44px. Test at 320px AND at ultrawide — both, not one.

## Step 7 — ESCAPE THE DEFAULT LOOK

Check against the cliché list: purple-gradient hero, identical rounded cards in a 3-grid, everything centered, emoji as icons, shadow soup. Make exactly one deliberate distinctive move; hold restraint everywhere else.

## Step 8 — VERIFY BY LOOKING (mandatory: run all 4 look-tests)

Screenshot the rendered result with the project's run/launch command (see its README or CLAUDE.md) or a headless-browser screenshot command (Playwright/Puppeteer) — the work is unverified until you have looked at it. Neither available → say plainly "I could not render it"; never claim a look you didn't take. Run all 4: resize test (narrow and wide), keyboard-tab test (focus visible), squint test, both-themes test. Then confirm the Step 5 states render correctly with real data. "It works" is not a design verdict.

## Hard rules

- Never style before hierarchy is decided.
- Never fix a value pixel-by-pixel in review — fix the scale it came from.
- Never skip states because "it's internal" — defaults compound for years.
- Never claim done without a screenshot in both themes.
