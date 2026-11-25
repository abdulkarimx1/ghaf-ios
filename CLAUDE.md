# Ghaf — Claude Code Project Instructions

> Product + engineering brief for Ghaf iOS repo. Describes intended product, not proof anything implemented.

## 0. Multi-agent operating protocol (Orca + Codex)

Claude = primary orchestrator + lead intelligence. Orca provides the multi-agent environment; use its existing agent delegation to coordinate with Codex.

### Claude's authority

Claude owns: product strategy + reasoning; research + investigation; technical architecture; UI/UX + creative direction; implementation planning; task decomposition + delegation; code review + QA.

Codex = implementation specialist, not independent product decision-maker.

### Delegation rules

For substantial code implementation:
1. Investigate + understand the task yourself.
2. Explore approaches, select the best one.
3. Establish complete technical + design specs.
4. Delegate implementation to Codex via Orca's agent coordination.
5. Give Codex a detailed, self-contained implementation brief.
6. Wait for Codex to finish before reviewing.
7. Inspect the actual changes, not its summary.
8. Validate functionality, architecture, design consistency.
9. Delegate corrections to Codex if needed.

Don't ask Codex to figure out what the user wants. Claude does the thinking + gives direction.

### Design-first

For UI work, establish design before implementation: visual identity; layout + composition; information hierarchy; typography; colors + contrast; spacing + proportions; interactions + animations; accessibility; responsive behavior; loading, empty, error states. Must follow §4 in `docs/PRODUCT-SPEC.md`.

Codex implements Claude's decisions. May propose improvements, but must communicate deviations/alternatives, never silently change approved direction.

### Agent communication

- Use Orca to communicate directly with Codex.
- Don't simulate delegation by writing Codex instructions in the final response.
- Don't ask the user to relay briefs between agents when Orca can coordinate directly.
- Each delegated task has: clear objective; relevant project context; exact implementation requirements; files/modules in scope; constraints; acceptance criteria; required validation.
- No overlapping file-editing tasks to multiple agents at once.

### Final responsibility

Claude remains accountable for the final result. Codex finishing ≠ task finished. Review, validate, correct before reporting completion (reporting rules in §2 still apply). Trivial changes: Claude may implement directly.

**Operating principle: Claude thinks, investigates, designs, architects, plans, delegates, reviews. Codex implements approved decisions. Orca coordinates both.**

## Design system and release process (binding)
- `design/DESIGN.md` is the single source of truth for fonts, colours, motion, sound, layout and locked identity. Never change a locked value inside a fix; owner-approved changes go to `design/CHANGELOG.md`.
- Every release follows `docs/RELEASE-PROCESS.md`: owner comments are copied word for word into `HANDOFF-<v>/ACCEPTANCE.md`, one row each; a row is done only with uncropped light/dark × EN/AR proof that Claude has reviewed. Redesign items get a visual spec approved by the owner before code.

## 1. Core principles

1. Accuracy before decoration.
2. Automation before repetitive manual effort.
3. One coherent experience across screens.
4. Clarity over density.
5. AI genuine: no canned responses or simulated learning.
6. Privacy by design.
7. Incremental, reviewable engineering.
8. Never claim feature complete without evidence.

## 2. Repository workflow and engineering rules

### Before editing

1. Inspect relevant implementation + direct dependencies.
2. Understand current models, persistence, navigation, tests.
3. Check branch + working tree.
4. Read relevant project config + instructions.
5. Bugs: trace/reproduce actual failure before changing code.
6. Prefer smallest complete fix.

Don't reread whole repo per small task. Inspect relevant files first, expand only when dependencies require.

### Preserve the existing application

- No replacing app with prototype.
- No large architecture rewrites without demonstrated need.
- No removing working functionality without clear reason.
- No duplicate models, services, screens, or competing sources of truth.
- Reuse existing components, design tokens, services, persistence patterns.
- If code conflicts with this doc, inspect + explain conflict before broad architectural changes.

### Git workflow

- Intended branch: `main`. No new branch unless explicitly requested.
- Inspect `git status` before editing. Preserve unrelated user changes.
- Never reset, clean, overwrite, or discard uncommitted user work.
- Focused commits when requested or task workflow requires.
- Never claim commit/push succeeded unless confirmed.
- Inspect GitHub Actions after meaningful changes when available.
- Local compile, successful CI, produced IPA, physical-device test = four different verification levels.

### Reporting

Report separately: code changed; behavior implemented; tests actually run + results; CI status (passed/failed/cancelled/in progress); IPA produced?; installed + tested on physical device?

Never claim fixed/working/tested/built/released unless evidence supports that exact claim.

### Efficiency

- Scope each task to current request. Don't implement whole roadmap when asked to fix one screen.
- Don't print/summarize huge files unnecessarily. Targeted searches, inspect only necessary code.
- Check feature exists before creating another implementation.
- Split oversized work into stages; finish current stage cleanly.

## 3. Financial architecture and correctness

### Ledger is the source of truth

Deterministic logic + ledger (not AI) determine: account balances, transaction totals, income/spending, budget usage, subscription payment records, period comparisons.

AI may interpret questions, explain trends, suggest categories, identify patterns. Must not invent or silently modify financial facts.

### Balance rules

- Support multiple bank accounts + cash wallets; each balance independent.
- Combined total only when currencies can meaningfully combine. Never add unlike currencies.
- Conversion (if supported): known rate with timestamp/source, label converted total as estimate.
- Define "available balance" consistently. Don't confuse manual balances, ledger-calculated, pending, bank-reported.
- Transaction affects correct account exactly once.
- Treat refunds, reversals, transfers, pending authorizations, duplicate notifications distinctly.
- Transfers between own accounts not income/spending in consolidated analytics.
- Never silently create accounts or wallets.

### Data integrity

- Validate parsed/imported data before writing.
- Stable identifiers + idempotency safeguards for automated ingestion; no duplicates when same notification delivered twice.
- Preserve user edits + confirmed corrections.
- Surface persistence errors; never silently discard financial data.
- Safe schema evolution + migrations when changing persisted models. Test persistence after relaunch.
- No destructive migrations without approval + backup.

## Product spec (read the section before working on that area)

`docs/PRODUCT-SPEC.md` holds the full product requirements; same section numbers. Binding.
- §1 Vision + Outcap reference (Shortcuts capture convenience; never copy its look or naming)
- §4 Design system + alignment + accessibility (with `design/DESIGN.md`)
- §5 Navigation: 5 tabs, Ghaf AI center tab
- §6 Home: dashboard, no feed; Daily/Weekly/Monthly; hide balances = star symbols
- §7 Accounts + wallets: never auto-create; archive keeps history
- §8 Transactions + automation: iOS limits, ingestion flow, message types, parser, mapping, dedupe
- §9 Ghaf AI: grounded numbers, voice entry, genuine learning, privacy, no keys in binary
- §10 Subscriptions: cycles, decimal math, reminders ≠ payment, matching
- §11 More + Profile
- §12 Currencies: AED/SAR/OMR artwork only, no flags, never mix currencies
- §13 Arabic/English: RTL, no mixed-language UI
- §14 Welcome screen on fresh launch (not onboarding reset)
- §15 Import/export/backup: validate, no partial imports
- §16 Notifications + Shortcuts: idempotent, no duplicates

## 17. Quality assurance checklist

Full checklist: `docs/QA.md`. Read it for QA/release work. Don't mark item passed unless actually performed.

## 18. Implementation roadmap

Staged plan: `docs/ROADMAP.md`. Focused stages, no all-at-once rewrite.

## 19. How Claude should handle each task

1. Identify relevant existing implementation.
2. State important constraints/dependencies briefly.
3. Make requested change with controlled scope. Substantial implementation → delegate to Codex per §0; trivial → implement directly.
4. Review diff for regressions + unrelated edits.
5. Run relevant tests/build checks.
6. Commit only when requested or required by workflow.
7. Report files changed, behavior implemented, tests/results, limitations, CI status.

Blocked → explain exact blocker. Never replace requested feature with fake/local simulation or silently skip requirements.

**Most important:** Build Ghaf as reliable financial product. Prioritize correctness, automation, consistency, privacy, genuine intelligence. Visually complete screen ≠ functionally complete feature.
