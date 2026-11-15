# Ghaf — Claude Code Project Instructions

> Persistent product and engineering brief for Claude Code in the Ghaf iOS repository.
> This document describes the intended product; it is not proof that any feature is implemented.

## 1. Product vision

Ghaf is an iOS personal finance companion focused on a reliable, understandable view of money across multiple bank accounts, wallets, transactions, budgets, and recurring subscriptions.

The product must feel like one coherent financial application, not a collection of unrelated screens.

### Product reference: Outcap

Use **Outcap** as a reference for the transaction automation experience, especially the convenience of using iOS Shortcuts to capture bank notification or message content and pass it into the app.

- Do not copy Outcap's visual identity or assume its internal architecture.
- Ghaf must have its own design language.
- The desired outcome is similar convenience: users should not need to manually log every bank transaction.
- Cash transactions may still require manual entry unless a reliable supported capture mechanism exists.

### Core principles

1. Accuracy before decoration.
2. Automation before repetitive manual effort.
3. One coherent experience across all screens.
4. Clarity over information density.
5. AI must be genuine, not canned responses or simulated learning.
6. Privacy by design.
7. Incremental, reviewable engineering.
8. Never claim a feature is complete without evidence.

## 2. Repository workflow and engineering rules

### Before editing

1. Inspect the relevant existing implementation and direct dependencies.
2. Understand current models, persistence, navigation, and tests.
3. Check the current branch and working tree.
4. Read relevant project configuration and existing instructions.
5. For bugs, trace or reproduce the actual failure before changing code.
6. Prefer the smallest complete fix.

Do not reread the entire repository for every small task. Inspect relevant files first and expand only when dependencies require it.

### Preserve the existing application

- Do not replace the app with a prototype.
- Do not rewrite large parts of the architecture without a demonstrated need.
- Do not remove working functionality without a clear reason.
- Do not create duplicate models, services, screens, or competing sources of truth.
- Reuse existing components, design tokens, services, and persistence patterns.
- If the code conflicts with this document, inspect the conflict and explain it before broad architectural changes.

### Git workflow

- The intended branch is `main`.
- Do not create another branch unless explicitly requested.
- Inspect `git status` before editing.
- Preserve unrelated user changes.
- Never reset, clean, overwrite, or discard uncommitted user work.
- Make focused commits when requested or when the established task workflow requires them.
- Never claim a commit or push succeeded unless confirmed.
- Inspect GitHub Actions after meaningful changes when available.
- A local compile, successful CI run, produced IPA, and physical-device test are four different levels of verification.

### Reporting

Report separately:
- What code changed.
- What behavior was implemented.
- What tests actually ran and their results.
- Whether CI passed, failed, was cancelled, or remains in progress.
- Whether an IPA was produced.
- Whether it was installed and tested on a physical device.

Never claim something is fixed, working, tested, built, or released unless evidence supports that exact claim.

### Efficiency

- Keep each task scoped to the current request.
- Do not implement the whole roadmap when asked to fix one screen.
- Avoid printing or summarizing huge files unnecessarily.
- Use targeted searches and inspect only necessary code.
- Check whether a feature already exists before creating another implementation.
- Split oversized work into stages and finish the current stage cleanly.

## 3. Financial architecture and correctness

### Ledger is the source of truth

Deterministic application logic and the financial ledger—not AI—must determine:
- Account balances.
- Transaction totals.
- Income and spending.
- Budget usage.
- Subscription payment records.
- Period comparisons.

AI may interpret questions, explain trends, suggest categories, and identify patterns. It must not invent or silently modify financial facts.

### Balance rules

- Support multiple bank accounts and cash wallets.
- Keep each account's balance independent.
- Show a combined total only when currencies can be meaningfully combined.
- Never add unlike currencies as if they were the same currency.
- If conversion is supported, use a known rate with timestamp/source and label the converted total as an estimate.
- Define “available balance” consistently. Do not confuse manually entered balances, ledger-calculated balances, pending transactions, and bank-reported balances.
- A transaction must affect the correct account exactly once.
- Treat refunds, reversals, transfers, pending authorizations, and duplicate notifications distinctly.
- Transfers between the user's own accounts must not count as income or spending in consolidated analytics.
- Never silently create accounts or wallets.

### Data integrity

- Validate parsed and imported data before writing.
- Use stable identifiers and idempotency safeguards for automated ingestion.
- Prevent duplicate creation when the same notification is delivered more than once.
- Preserve user edits and confirmed corrections.
- Surface persistence errors; never silently discard financial data.
- Use safe schema evolution and migrations when changing persisted models.
- Test persistence after relaunch.
- Avoid destructive migrations without approval and backup.

## 4. Design system and visual direction

Ghaf should be minimal, modern, confident, readable, and visually distinctive without excessive decoration.

- Use larger, stronger typography where appropriate.
- Make financial amounts and primary actions easy to scan.
- Prefer clear hierarchy and intentional whitespace.
- Avoid excessive nested cards, borders, shadows, random icon styles, and tiny tap targets.
- Keep colors, typography, spacing, shapes, and components consistent across tabs.
- Inspect existing design tokens before introducing new ones.
- Extend or consolidate the existing design system rather than creating parallel systems.
- Ensure light/dark appearance behavior is coherent if both are supported.

### Alignment

The overall presentation should feel intentionally center-aligned rather than defaulting to left alignment everywhere.

Center alignment is especially suitable for main headings, key financial totals, welcome/onboarding content, empty states, AI entry, and primary overview interactions.

Do not force every component to be centered. Lists, dense data, form fields, and detailed transaction information may need conventional leading alignment. Use alignment intentionally.

### Accessibility and layout

- Respect iOS safe areas.
- Support Dynamic Type where feasible.
- Add accessible labels to icon-only controls.
- Maintain sufficient contrast.
- Avoid clipped content and fixed heights that break with localization.
- Test smaller and larger device sizes.
- Use comfortable touch targets.
- Do not rely on color alone to communicate meaning.

## 5. Main navigation

The intended five destinations are:

1. Home
2. Transactions
3. Ghaf AI
4. Subscriptions
5. More

**Ghaf AI must be the center tab (third of five)** and must feel like a primary feature, not a decorative chatbot.

- Keep labels and icons clear.
- Use consistent selected/unselected states.
- Preserve navigation state where appropriate.
- Avoid duplicate destinations.
- Ensure every tab opens a functional screen.
- Do not present placeholder screens as finished features.

## 6. Home screen

Home is the financial dashboard. It should focus on available balances, accounts, and useful financial summaries—not a long transaction feed.

### Content

Where supported by real data, show:
- Combined available balance, only when currency treatment is valid.
- Individual account balances.
- Account names and currencies.
- Spending and income summaries.
- Budget status.
- A period-based overview.

Do not assume the user has one bank or one wallet.

### Transactions feed

Remove the long transaction list from Home. Transactions have a dedicated tab. A small shortcut to Transactions is acceptable if useful, but do not recreate the feed.

### Daily / Weekly / Monthly

Provide a clear selector or interactive overview for:
- Daily
- Weekly
- Monthly

The selected period must actually update all relevant statistics, including spending, income, comparisons, budget progress, and charts.

Define period boundaries consistently using the user's locale, calendar, and timezone. Handle the locale's week start. If there is no data, show a useful empty state rather than fabricated values.

### Hide balances

Provide an eye control to hide/reveal sensitive amounts.

When hidden:
- Replace sensitive amounts with a small group of star-shaped symbols.
- Do not use dashes, generic asterisks, or unrelated placeholder icons.
- Apply the representation consistently.
- Do not alter underlying values or calculations.
- Keep visibility state predictable across navigation and relaunch, according to the app's privacy design.

## 7. Accounts and wallets

Users should be able to add bank accounts and cash wallets, edit details, archive/remove accounts safely, set currency and opening balance, view calculated balance, and assign transactions.

Rules:
- Do not create empty wallets automatically.
- Do not create placeholder accounts without explicit user action.
- Keep account identity stable when renamed.
- Avoid loose substring-only matching.
- Use confirmed mappings and robust matching.
- If account identity is uncertain, send the transaction to review.
- Archiving must not erase historical transactions.
- Explain consequences and use safeguards when removing an account.

## 8. Transactions and automation

### Product goal

Minimize manual transaction entry. Cash may still require manual entry.

Use Outcap as a reference for Shortcuts-based capture convenience. Do not assume iOS permits an ordinary app to read every other app's notifications.

### iOS constraints

- Do not claim an ordinary iOS app can freely read notifications from other apps.
- Use user-configured Shortcuts, supported share actions, App Intents, or other permitted mechanisms.
- Explain required setup clearly.
- Do not promise unsupported background automation.
- Keep the workflow as automatic and low-friction as iOS permits.

### Intended ingestion flow

1. A supported notification/message is made available to a configured Shortcut or supported integration.
2. The Shortcut passes text or structured data to Ghaf through an App Intent or supported handoff.
3. Ghaf parses the content.
4. Ghaf identifies transaction details and confidence.
5. Ghaf checks for duplicates.
6. Ghaf assigns category/account when sufficiently confident.
7. Ghaf records the transaction or sends it to Needs Review.
8. The ledger updates account balances and analytics.

### Message and transaction types

Distinguish:
- Purchase.
- Income/deposit.
- Transfer.
- Cash withdrawal.
- Refund.
- Reversal.
- Pending authorization.
- Balance alert.
- OTP.
- Promotional message.
- Other non-transaction message.

Never create a financial record from an OTP, marketing message, generic balance alert, or unconfirmed event.

### Parser fields

Extract where present:
- Amount and currency.
- Merchant/description.
- Transaction direction/type.
- Date and time.
- Account/card reference.
- Available balance as a separate data point, not another transaction.
- Reference or transaction ID.
- Confidence and useful review information.

Support Arabic and English, Arabic-Indic and Western digits, common UAE amount/date formats, and currency abbreviations.

Potential UAE sources include Mashreq, iVESTOR, Ruya, and others. Do not assume all formats are known. Keep parsing modular and testable.

### Account mapping

Learn confirmed mappings between notification clues and the user's account records. For example, if the user has an account named “Ivestor,” relevant iVESTOR messages should map to it when evidence supports the match.

Do not silently map using vague name similarity.

### Duplicates, pending transactions, and reversals

Use idempotency keys where possible, based on stable source IDs or carefully designed fingerprints.

Handle duplicate Shortcut runs, repeated notifications, pending-to-posted updates, reversals, refunds, and legitimate repeated purchases.

Do not deduplicate solely by amount and date if that could merge separate purchases.

### Transaction UI

Users must be able to view/search/filter transactions, open details, edit relevant fields, change categories/accounts, add notes, review automatic classifications, and delete records with clear confirmation or undo where feasible.

Fix blank transaction editors, blank category pickers, and broken navigation. Do not leave interactive controls that lead nowhere.

## 9. Ghaf AI

### Role and capabilities

Ghaf AI is the central financial assistant. It must be a real assistant connected to the user's data, not a static chat UI with generic canned answers.

Build toward:
- Arabic and English conversation.
- Natural-language financial questions.
- Voice transaction entry.
- Transaction categorization suggestions.
- Merchant and account recognition.
- Spending and budget analysis.
- Recurring spending detection.
- Subscription awareness.
- Period comparisons.
- Useful reminders and explanations.

Example questions:
- “How much did I spend this week?”
- “Where did most of my money go?”
- “How much did I spend on restaurants this month?”
- “How much do I have across my accounts?”
- “Am I spending more than last month?”
- “Which subscriptions are due soon?”
- “كم صرفت هالأسبوع؟”
- “وين أكثر مكان صرفت فيه؟”
- “سجلت ٣٥ درهم غداء.”

### Grounded financial answers

For numerical questions:
1. Retrieve relevant records.
2. Apply deterministic calculations.
3. Respect account and currency boundaries.
4. State the period and explain the result.
5. Never invent missing data.

A language model must not calculate authoritative balances from an unverified prompt summary.

### Voice transaction entry

Support natural Arabic and English such as:
- “I spent 35 dirhams on lunch.”
- “Paid 120 AED for fuel using Mashreq.”
- “اشتريت قهوة بعشرين درهم.”
- “دفعت ٥٠ درهم بنزين.”

Extract amount, currency, merchant/description, category, type, account if known, and date if specified.

Ask a concise clarification if an essential field is unclear. Do not silently guess. If an utterance contains multiple purchases, create separate transaction candidates. Confirm or review where necessary.

### Genuine learning

Learning must use actual user actions and confirmed corrections, such as:
- Changing a suggested category.
- Changing the account assigned to a merchant.
- Editing a merchant name.
- Confirming/rejecting a suggested transaction.
- Repeatedly using a consistent category for a merchant or pattern.

Store useful structured feedback, for example:
- Normalized merchant key.
- Confirmed category.
- Confirmed account mapping.
- User preference.
- Confidence/count.
- Last-confirmed timestamp.
- Source and parser/model version.

Use learned data to improve future suggestions. Prefer transparent deterministic mappings for repeated high-confidence corrections.

Describe accurately whether a capability is a local preference/mapping, server-side retrieval memory, trained model, or recent-context suggestion. Do not claim model training if only a local rule is stored.

### Hybrid architecture and privacy

Use on-device logic where practical for local preferences, confirmed mappings, basic parsing/categorization, offline behavior, and deterministic calculations.

Use a secure backend for advanced cloud reasoning if needed.

- Never embed provider API keys or secrets in the iOS binary.
- Inspect whether a backend already exists before proposing another.
- Reuse existing infrastructure where appropriate.
- Explain tradeoffs before introducing a new service.
- Minimize financial data shared.
- Send only context needed for the current task.
- Use authenticated requests and secure transport.
- Define retention and deletion behavior.
- Do not send full transaction history on every request by default.
- Provide controls to inspect, reset, and disable learned preferences.
- Make AI data use understandable.

### AI interface

The AI screen should include a clear starting point, useful suggested questions, voice/text input, readable conversation, and clear distinctions between answers, suggestions, and transactions awaiting confirmation.

Include loading, error, empty, and offline states. Avoid fake thinking animations and fabricated responses.

## 10. Subscriptions

Subscriptions have a dedicated tab and integrate with the rest of Ghaf.

### Subscription data

Support:
- Name.
- Amount and currency.
- Billing cycle.
- Next payment date.
- Category.
- Payment account.
- Reminder preference.
- Notes.
- Active/inactive state.
- Creation and update dates.

Billing cycles: weekly, monthly, quarterly, yearly. Design for future extensibility.

### Overview

Show active subscriptions, upcoming payment dates, monthly equivalent cost, annual cost, and payment history where available. Clearly identify estimated monthly equivalents for non-monthly cycles. Use correct decimal arithmetic, not integer division.

### Reminders

- Use local notifications where appropriate.
- Request permission with a clear explanation.
- Allow reminder timing preferences.
- Reschedule when date, cycle, or status changes.
- Cancel when deleted or deactivated.
- Handle denied permissions gracefully.
- A reminder is not proof that a payment happened.

### Transaction matching

When a real transaction is ingested, compare it with active subscriptions using merchant, amount, date window, and account evidence.

- Use confidence thresholds.
- Ask for confirmation when uncertain.
- Record confirmed payments in history.
- Advance the next payment date only after confirmed payment or a clearly defined trusted rule.
- Prevent duplicate payment records and duplicate balance deductions.
- A reminder must never deduct money. Only a confirmed transaction affects the ledger.

## 11. More screen and Profile

### More screen

Simplify into a few clear groups:

**Profile**
- Personal details.
- Profile image or initials.
- Language and personal preferences.

**Accounts**
- Bank accounts and wallets.

**Preferences**
- Currency.
- Appearance.
- Language.
- Notifications.

**Ghaf AI**
- Learning preferences.
- Privacy controls.
- Learned mappings/preferences.
- Reset learning data.

**Data**
- Import.
- Export.
- Backup/restore if supported.

**About**
- App information.
- Help and support.

Avoid a long cluttered list of unrelated cards. Every row must lead to a working destination.

### Profile

Create a clear, properly designed profile screen with supported editable fields, consistent spacing, and typography. Do not invent authentication or profile synchronization if there is no backend for it.

## 12. Currencies and money formatting

The currency selector and currency display require correction.

### Dedicated artwork

Use proper currency-specific artwork only for:
- UAE Dirham (AED).
- Saudi Riyal (SAR).
- Omani Rial (OMR).

Remove generic currency icons and unrelated placeholders. Do not substitute country flags.

For currencies without dedicated artwork, show the currency abbreviation as text.

### Formatting and calculations

- Keep currency codes and amounts paired correctly.
- Use locale-aware number formatting.
- Avoid ambiguous symbols where currencies share symbols.
- Use consistent formatting across accounts, transactions, subscriptions, and summaries.
- Never aggregate different currencies without a real conversion rate.
- When conversion is supported, show the rate and timestamp.
- Changing preferred display currency must not silently change historical transaction currencies.

## 13. Arabic, English, and localization

Support Arabic and English throughout.

- Arabic uses proper RTL behavior.
- English uses proper LTR behavior.
- Prefer semantic leading/trailing alignment over hardcoded left/right positioning.
- Handle directional icons appropriately.
- Do not manually reverse components unnecessarily if SwiftUI layout direction handles it.

Language switching must update navigation, headings, buttons, forms, empty states, categories, transaction types, dates, currency formatting, notifications, and AI interface/prompts.

Avoid mixed-language UI unless user-provided merchant names or notes naturally remain in their original language. Check clipping and button widths in both languages.

## 14. Welcome screen and onboarding

The supplied welcome artwork should be the actual welcome screen.

The user wants the welcome artwork to appear whenever the app is freshly launched after being completely removed from the iOS app switcher.

Important:
- This is not the same as restarting first-time onboarding.
- Do not erase user data or reset accounts/preferences.
- Do not force the full onboarding flow on every launch.
- Returning from background is not a fresh process launch.
- Verify asset catalog membership and target packaging.
- Verify actual launch behavior; an `Image` reference alone does not prove the asset is packaged.

If iOS launch-screen restrictions apply, explain what can be done with the native launch screen and what requires an in-app welcome view.

## 15. Import, export, and backup

The existing JSON import workflow must work.

### Import

- Let users select a supported Ghaf JSON file.
- Validate schema/version before importing.
- Show understandable errors for invalid or unsupported files.
- Never silently do nothing.
- Avoid partial imports that leave inconsistent data.
- Handle duplicate imports safely where possible.
- Preserve accounts, transactions, categories, settings, subscriptions, and relevant preferences.

### Export

- Export the data supported by the current schema.
- Use a versioned, documented format.
- Do not expose unnecessary secrets.
- Clearly state what is included and excluded.

Add schema/version handling as data models evolve. Do not claim compatibility with formats that have not been tested.

## 16. Notifications and Shortcuts

Notifications should be useful, accurate, and user-controlled. Distinguish transaction review, subscription reminders, budget alerts, and optional financial reminders.

- Prevent duplicate notifications for the same event.
- Provide appropriate settings.
- Handle denied permissions gracefully.
- Make Shortcut setup understandable.
- Use clear App Intent names and parameters.
- Validate incoming data.
- Return useful success/failure results.
- Make ingestion idempotent.
- Avoid requiring manual app navigation for every transaction.

## 17. Quality assurance checklist

Use this checklist for relevant changes. Do not mark a test as passed unless it was actually performed.

### Navigation and UI
- [ ] Five tabs in the intended order.
- [ ] Ghaf AI is the center tab.
- [ ] Every tab opens a functional screen.
- [ ] Home has no long transaction feed.
- [ ] Daily/Weekly/Monthly updates real data.
- [ ] Hidden balances use the star representation.
- [ ] More is simplified and navigable.
- [ ] Profile actions work.
- [ ] No blank editor or category screens.
- [ ] No clipped content or safe-area overlap.

### Accounts and ledger
- [ ] Multiple accounts supported.
- [ ] No empty accounts created automatically.
- [ ] Each transaction affects the correct account exactly once.
- [ ] Transfers do not inflate income/spending.
- [ ] Refunds and reversals handled distinctly.
- [ ] Different currencies are not incorrectly added.
- [ ] Balances persist after relaunch.

### Transactions and automation
- [ ] Arabic and English parsing tested.
- [ ] Multiple purchases remain separate.
- [ ] OTP/promotional messages do not create transactions.
- [ ] Duplicate Shortcut runs do not duplicate records.
- [ ] Account matching uses evidence.
- [ ] Low-confidence transactions go to review.
- [ ] Editing and category changes work.
- [ ] JSON import works and reports errors.

### Ghaf AI
- [ ] Numerical answers use actual ledger data.
- [ ] AI does not invent balances or transactions.
- [ ] Arabic/English voice entry works where supported.
- [ ] Confirmed corrections influence future suggestions.
- [ ] Learning behavior is accurately described.
- [ ] No API secrets in app bundle.
- [ ] Privacy/reset controls work.

### Subscriptions
- [ ] Add/edit/delete works.
- [ ] Billing cycle calculations are correct.
- [ ] Reminders schedule and reschedule.
- [ ] Deactivated subscriptions stop reminders.
- [ ] Confirmed payments match without double-counting.
- [ ] Payment history is preserved.
- [ ] Reminders do not deduct balances.

### Localization and launch
- [ ] Arabic RTL works.
- [ ] English LTR works.
- [ ] Language switch updates the whole UI.
- [ ] AED, SAR, and OMR artwork is correct.
- [ ] Other currencies use text abbreviations.
- [ ] Welcome artwork is packaged.
- [ ] Fresh-process launch behavior is correct.
- [ ] Existing data survives launch and updates.

## 18. Implementation roadmap

Do not attempt a massive all-at-once rewrite. Work in focused stages.

### Stage 1 — Inspect and stabilize
- Inspect repository, branch, build configuration, and latest CI.
- Identify compile errors and broken flows.
- Fix persistence and navigation issues.
- Fix blank transaction/category screens.
- Fix language switching and safe-area problems.
- Fix multiple-account and balance inconsistencies.
- Verify welcome asset and launch behavior.

### Stage 2 — Core UI
- Refine shared design system.
- Redesign Home around balances and overview.
- Remove Home transaction feed.
- Implement Daily/Weekly/Monthly interaction.
- Implement hidden-balance stars.
- Simplify More and improve Profile.
- Confirm five-tab navigation with Ghaf AI centered.

### Stage 3 — Accounts and transaction reliability
- Fix account lifecycle and matching.
- Improve transaction ingestion and duplicate prevention.
- Improve Arabic/English parsing.
- Fix voice transaction splitting and merchant cleanup.
- Complete transaction editing and review.
- Repair JSON import/export.

### Stage 4 — Subscriptions
- Complete subscription CRUD and persistence.
- Implement reminders.
- Implement payment history.
- Connect confirmed transaction matching.
- Add subscription statistics.

### Stage 5 — Ghaf AI
- Complete AI interface.
- Implement voice input.
- Implement deterministic financial query tools.
- Add secure backend integration if required.
- Implement confirmed-feedback learning.
- Add privacy, inspection, and reset controls.

### Stage 6 — QA and delivery
- Run relevant automated tests.
- Run a full build.
- Check GitHub Actions.
- Fix build failures.
- Produce an IPA only after a successful build.
- Report what is and is not verified.
- Do not imply physical-device testing unless performed.

## 19. How Claude should handle each task

For every task:

1. Identify the relevant existing implementation.
2. State important constraints or dependencies briefly.
3. Make the requested change with controlled scope.
4. Review the diff for regressions and unrelated edits.
5. Run relevant tests/build checks.
6. Commit only when requested or required by the established workflow.
7. Report files changed, behavior implemented, tests/results, limitations, and CI status.

If blocked, explain the exact blocker. Do not replace the requested feature with a fake/local simulation or silently skip requirements.

**Most important:** Build Ghaf as a reliable financial product. Prioritize correctness, automation, consistency, privacy, and genuine intelligence. A visually complete screen is not a functionally complete feature.
