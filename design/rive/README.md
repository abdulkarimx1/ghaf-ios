# Rive files
Runtime: rive-ios (Swift Package `https://github.com/rive-app/rive-ios`), added only when the first .riv ships.
For each file list: name, artboard, state machine, inputs (name + type), where it is used, Reduce Motion fallback.

## Tooling (installed 2026-11-25)
- Rive CLI 1.11 via Homebrew (`brew install --cask rive-app/tap/rive-cli`), analytics off.
- Project: `design/rive/ghaf-motion/` — scenes are written as text (`scene.rml`) by Claude/Codex, previewed with `rive design/rive/ghaf-motion`, checked with `--verify`.
- Saving a `.riv` (`--publish=local`) needs `rive login` (owner's account). Free plan = watermarked .riv and 50 publishes/month; Cadet or higher = no watermark.
- Shipping in the app: add the rive-ios Swift package only when the first approved .riv is ready.
