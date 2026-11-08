# Ghaf Product Correction & Redesign Brief

Status: approved direction from product feedback; implementation and device validation pending.
Working branch: `ghaf-v2-corrections`
Base branch: `main`

## Product direction

Ghaf is a bold, minimal, UAE-rooted personal finance app. The interface should reduce cognitive load: strong typography, clear hierarchy, larger controls, fewer competing elements, and compact screens. The primary home experience should fit without vertical scrolling on supported iPhone sizes; secondary detail can be progressively disclosed.

## 1. Welcome and onboarding

- Replace the current generic launch/onboarding presentation with the approved full-screen Ghaf welcome artwork supplied by the product owner.
- Preserve the image composition, Arabic wordmark, translucent panel, desert/Ghaf tree/camel scene, and UAE signature/flag.
- Welcome artwork is the app's actual introduction screen, not merely a splash animation or decorative reference.
- First-run flow must ask for language before any profile introduction or user-facing onboarding copy.
- After language selection, show a personal, card-led profile introduction/setup. All following steps must use the selected language.
- On a language change in Settings, persist the choice, reset the root UI state, show the welcome screen again, and rebuild the entire interface in the selected language/direction. Preserve financial data and account state. Avoid partial in-place text swaps that leave stale layout/state.

## 2. Home screen and navigation

- Home should be bold, minimal, and non-scrolling on supported iPhone sizes. Prioritize the most useful balance and spending information; move secondary detail to dedicated views or compact progressive disclosure.
- Use the GO Club reference for typography weight, hierarchy, button scale, spacing, and confidence—not as a literal visual copy.
- Home tab re-selection gesture: first activation shows daily stats/transactions; second activation cycles to weekly; third activation cycles to monthly. Define and test a deterministic cycle, visible period state, and reset behavior when navigating away or after monthly.
- Ensure all tab/home controls are genuinely tappable and have clear hit targets.

## 3. Visual system

- Apply the glass treatment across the app as a coherent design language, not only to the bottom tab/icon row. Establish reusable materials for cards, sheets, floating controls, navigation surfaces, and selected states.
- Glass must not reduce text contrast, obscure transaction data, or make controls look disabled. Use solid/opaque fallbacks where accessibility or dense data requires them.
- Increase button size and visual weight. Reduce unnecessary decorative elements and per-screen information density.
- Replace weak/inconsistent icons with a coherent, polished icon system. Prefer supplied custom currency artwork and a consistent SF Symbols/custom-vector family; avoid emoji and arbitrary mixed icon styles.
- Add three social/contact destinations (Instagram, TikTok, email). Until real URLs/addresses are supplied, render clearly marked placeholders that are not presented as working links.

## 4. Seven UAE city themes

- The seven city themes must be genuinely distinct visual themes, not one palette with seven accent colors.
- Each theme needs its own visible, city-inspired line-art background/illustration, composition, and supporting motif.
- Keep the line art visible at normal usage size while ensuring it stays behind content and does not reduce legibility.
- Maintain a common Ghaf design system so the seven themes still feel like one product.

## 5. GCC currencies

Initial scope: AED, SAR, OMR, QAR, KWD, BHD.
- Use the supplied/custom currency symbol artwork or approved vector assets. Do not substitute currency codes rendered as text or country flags for the requested currency icons.
- Show the correct icon consistently in account cards, balances, transaction rows, account setup, and currency selection.
- Keep ISO currency codes as underlying data/accessible labels; icons are visual presentation only.
- Preserve per-account currency. Never sum unlike currencies without an explicit exchange-rate conversion and clear converted-total label.
- Keep the currency model extensible for later international support.

## 6. Automatic transaction capture

- The target experience is Outcapt-like: automatically capture supported bank activity through user-configured Apple Shortcuts personal automations, with manual logging primarily needed for cash and unsupported sources.
- Do not claim Ghaf can read all third-party app notifications directly. iOS privacy and Shortcuts trigger/variable availability constrain what can be captured; validate the exact supported trigger and available title/body/app variables on-device.
- Provide a bank-by-bank setup guide and clear diagnostics for missing fields, unsupported banks, parse failures, and duplicates.
- Preserve SMS/App Intent capture. Make title + body + app/sender available to parsing when Shortcuts exposes them.
- Ensure app and App Intent use the same correctly configured persistent store/container and that writes appear without relaunch.
- Duplicate handling must not permanently discard repeated identical purchases. Use a bounded deduplication window and test same-SMS/push duplicates against genuinely separate purchases.
- Test real redacted samples from each supported GCC bank before claiming bank coverage.

## 7. Voice transaction capture

- Recognition must handle Arabic and English regardless of the app's display language. UI locale must not force the spoken language.
- Improve speech recognition and parsing for mixed-language utterances, merchant names, amounts, currencies, dates, and transaction intent.
- Split one long spoken record into multiple transaction drafts where multiple purchases/transactions are described. Each draft must be editable before saving; never silently commit uncertain splits.
- Add an online AI parsing/enrichment option only with explicit user consent and transparent disclosure of what transcript data is sent, to which service, and why. Do not upload raw audio by default.
- Keep a reliable local/rule-based fallback when offline or when AI is disabled/unavailable. Do not imply the model learns from user data unless a real, disclosed learning mechanism exists.
- Add tests for Arabic, English, mixed-language speech, multiple transactions in one utterance, ambiguous amounts, and currency detection.

## 8. Import/export

- Fix JSON import for supported external app formats, with format detection, validation, preview, field mapping, duplicate handling, and an explicit confirmation step.
- Keep Ghaf backup restore distinct from third-party app import. Do not silently treat an unknown JSON file as a Ghaf backup.
- Report actionable errors and import summaries; do not replace existing data until validation and user confirmation succeed.

## 9. Privacy policy

- Replace generic/AI-sounding copy with a precise, readable policy that describes the current implementation, not planned capabilities.
- Explicitly explain local SwiftData storage, bank messages passed through Shortcuts/App Intents, speech/microphone permissions, any optional online AI processing, JSON backup/export, and what is not collected.
- Distinguish current behavior from planned features. Do not claim cloud sync, encryption, account security, or third-party processing that is not implemented and verified.
- Include contact details only when supplied by the owner; otherwise use a clearly identified placeholder during development.

## 10. Quality gates

- Do not merge to `main` or produce a release IPA until each phase builds and relevant tests pass.
- Test English and Arabic from a clean install and after switching language in Settings.
- Test on actual iPhone hardware for welcome artwork scaling, safe areas, home no-scroll layout, glass contrast, Shortcuts automation variables, speech recognition, and import flows.
- Provide a concise change log, known limitations, build result, and device-test checklist with every IPA.
- Keep implementation in this working branch until reviewed; do not silently overwrite approved product decisions.
