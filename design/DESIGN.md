# Ghaf design system — the single source of truth

> Binding for Claude and Codex in every build. A value here changes ONLY when the owner approves it, and the change is recorded in `design/CHANGELOG.md` with the date. Never "improve" a locked value inside a fix.

## 1. How the owner adds design material
| What | Where | Rule |
|---|---|---|
| Fonts (.otf/.ttf) | `Ghaf/Resources/Fonts/` + the licence (or receipt) in `design/fonts-licences/` | Claude registers it in `project.yml → UIAppFonts` and in §3 below. A font without a licence file is not shipped. |
| Inspo per screen (images, videos) | SSD: `/Volumes/SSK SSD/My Files/Ghaf APP/Inspo/<screen>/` | Videos stay on the SSD (too big for git). Claude extracts key frames into `design/inspo/<screen>/frames/` and writes `design/inspo/<screen>/NOTES.md`: what to copy, exact measurements, timings. |
| Rive animations (.riv) | `design/rive/` (source `.riv`) → copied to `Ghaf/Resources/Rive/` when shipped | One file per animation; state-machine and input names listed in `design/rive/README.md`. |
| Logo / app icon | `design/brand/` (master .ai/.svg + exports) | App icon generated from the master only. |
| Comments for a release | `HANDOFF-<version>/COMMENTS.md` (template: `design/COMMENTS-TEMPLATE.md`) | One numbered item per line, screenshots named after the item number. |

## 2. Locked identity (change only with owner approval)
- Default theme for proofs: **Graphite**, dark. Every screen must also pass light/dark × EN/AR.
- No palm / leaf / tree icons or motifs.
- Amount privacy mask: one dot per digit **including decimals**.
- Currency artwork only for AED, SAR, OMR; others as text code.
- Ghaf AI is the centre tab (3rd of 5).

## 3. Typography (current, locked)
| Role | English | Arabic |
|---|---|---|
| Display / headings | IBM Plex Sans | Thmanyah Serif Display Black |
| Body | IBM Plex Sans (variable) | IBM Plex Sans Arabic (Regular/Medium/SemiBold/Bold) |
| Numbers (amounts, charts, stats, keypad, widgets) | Geist (variable, tabular figures) via `GhafTypography.number` / `ghafNumberFont` | Geist has no Arabic-Indic digits; those glyphs use the system fallback |
Use only `GhafTypography.display / heading / body`. No `.system(size:)` for text in new screens.

## 4. Colour
Only tokens from `Ghaf/DesignSystem/GhafTheme.swift` (background, surface, elevatedSurface, primaryText, secondaryText, accent, accentContrast, glow, debit, credit, comfortable/close/over, outline). No hex literals in screens. Glows/gradients use the theme's own accent + glow (Graphite = silver).

## 5. Motion (locked defaults — every screen)
| Use | Value |
|---|---|
| Press feedback | scale 0.97, spring(duration 0.18, bounce 0) |
| Small reveal / popover | spring(duration 0.30, bounce 0.10) |
| Sheet / card / page | spring(duration 0.45, bounce 0.15) |
| Hero entrance (rare moments) | spring(duration 0.70, bounce 0.20), stagger 0.08–0.12 s |
| Drag | follows the finger 1:1, no easing while dragging; spring on release using the gesture velocity |
| Reduce Motion | no travel/scale; fades ≤ 0.2 s; loops paused |
Rules: animate transform/opacity only; every open has a matching close; tab switches and keyboard actions are instant; 60 fps on device is required (proof = Instruments/`sample`, not XCUITest time).
Rich motion (onboarding, splash, achievements, empty states, Pro) → Rive or Metal; routine UI → SwiftUI springs.

## 6. Sound + haptics
Files and choices: `docs/SOUNDS.md`. Sounds only for: orb on/off, transaction added (2.0 s after Save, 20%), delete, streak, tick. Every sound pairs with a haptic. Respect the silent switch.

## 7. Layout
Gutter 16 pt (phone). Touch targets ≥ 44 pt. Centre-align headings, totals, onboarding, empty states; lead-align lists and forms. RTL via layout direction, never by manually flipping containers.

## 8. Screen inventory (status per screen)
Keep `design/SCREENS.md` current: one row per screen → inspo folder, last approved build, owner-approved screenshot path.
