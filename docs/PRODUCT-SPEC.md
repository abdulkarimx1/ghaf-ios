# Ghaf — Product Spec

> Moved out of CLAUDE.md to save tokens. Section numbers kept; CLAUDE.md links here. Binding like CLAUDE.md: read the relevant section before working on that area.

## 1. Product vision

Ghaf: iOS personal finance companion. Reliable, understandable view of money across multiple bank accounts, wallets, transactions, budgets, recurring subscriptions. Must feel like one coherent app, not unrelated screens.

### Product reference: Outcap

Outcap = reference for transaction automation via iOS Shortcuts (capture bank notification/message, pass into app).
- Don't copy Outcap visual identity or assume its architecture. Ghaf has own design language.
- Goal: similar convenience; no manual logging of every bank transaction.
- Cash may still need manual entry unless reliable capture exists.

Core principles: see CLAUDE.md §1.

## 4. Design system and visual direction

Minimal, modern, confident, readable, distinctive without excess decoration.
- Larger, stronger typography where appropriate. Amounts + primary actions easy to scan.
- Clear hierarchy, intentional whitespace.
- Avoid excess nested cards, borders, shadows, random icon styles, tiny tap targets.
- Consistent colors, typography, spacing, shapes, components across tabs.
- Inspect existing tokens before adding new; extend/consolidate, no parallel systems.
- Coherent light/dark if both supported.

### Alignment

Overall presentation intentionally center-aligned, not left by default. Center suits: main headings, key totals, welcome/onboarding, empty states, AI entry, primary overview. Don't force everything centered: lists, dense data, form fields, transaction details may need leading alignment. Use alignment intentionally.

### Accessibility and layout

- Respect safe areas. Support Dynamic Type where feasible.
- Accessible labels on icon-only controls. Sufficient contrast.
- No clipped content or fixed heights breaking localization. Test small + large devices.
- Comfortable touch targets. Don't rely on color alone for meaning.

## 5. Main navigation

Five destinations: 1. Home 2. Transactions 3. Ghaf AI 4. Subscriptions 5. More

**Ghaf AI must be center tab (third of five)**, feel like primary feature, not decorative chatbot.
- Clear labels/icons; consistent selected/unselected states.
- Preserve navigation state where appropriate. No duplicate destinations.
- Every tab opens functional screen. No placeholder screens presented as finished.

## 6. Home screen

Home = financial dashboard: balances, accounts, useful summaries. Not long transaction feed.

### Content

Where real data supports: combined available balance (only when currency treatment valid); individual account balances; account names + currencies; spending/income summaries; budget status; period overview. Don't assume one bank or wallet.

### Transactions feed

No long transaction list on Home; Transactions has own tab. Small shortcut to Transactions OK; don't recreate feed.

### Daily / Weekly / Monthly

Selector or interactive overview for Daily/Weekly/Monthly. Selected period must update all relevant stats: spending, income, comparisons, budget progress, charts. Period boundaries consistent with user's locale, calendar, timezone; handle locale week start. No data → useful empty state, not fabricated values.

### Hide balances

Eye control hides/reveals sensitive amounts. When hidden:
- Replace amounts with small group of star-shaped symbols. No dashes, generic asterisks, or unrelated icons.
- Apply consistently. Don't alter underlying values/calculations.
- Visibility state predictable across navigation + relaunch per privacy design.

## 7. Accounts and wallets

Users can add bank accounts + cash wallets, edit details, archive/remove safely, set currency + opening balance, view calculated balance, assign transactions.

- No automatic empty wallets or placeholder accounts without explicit user action.
- Account identity stable when renamed.
- No loose substring-only matching; use confirmed mappings + robust matching. Uncertain identity → review.
- Archiving must not erase historical transactions.
- Explain consequences + safeguards when removing account.

## 8. Transactions and automation

### Product goal

Minimize manual entry; cash may still need it. Outcap = reference for Shortcuts capture convenience. Don't assume iOS lets ordinary app read other apps' notifications.

### iOS constraints

- Don't claim ordinary iOS app can freely read other apps' notifications.
- Use user-configured Shortcuts, supported share actions, App Intents, or other permitted mechanisms.
- Explain required setup clearly. Don't promise unsupported background automation.
- Keep workflow as automatic + low-friction as iOS permits.

### Intended ingestion flow

1. Supported notification/message reaches configured Shortcut or integration.
2. Shortcut passes text/structured data to Ghaf via App Intent or supported handoff.
3. Ghaf parses content.
4. Ghaf identifies transaction details + confidence.
5. Ghaf checks duplicates.
6. Ghaf assigns category/account when confident enough.
7. Ghaf records transaction or sends to Needs Review.
8. Ledger updates balances + analytics.

### Message and transaction types

Distinguish: purchase; income/deposit; transfer; cash withdrawal; refund; reversal; pending authorization; balance alert; OTP; promotional; other non-transaction.

Never create financial record from OTP, marketing message, generic balance alert, or unconfirmed event.

### Parser fields

Extract where present: amount + currency; merchant/description; direction/type; date + time; account/card reference; available balance (separate data point, not another transaction); reference/transaction ID; confidence + review info.

Support Arabic + English, Arabic-Indic + Western digits, common UAE amount/date formats, currency abbreviations. Potential UAE sources: Mashreq, iVESTOR, Ruya, others. Don't assume all formats known. Parsing modular + testable.

### Account mapping

Learn confirmed mappings between notification clues and user accounts (e.g. account "Ivestor" ← iVESTOR messages when evidence supports). Never silently map by vague name similarity.

### Duplicates, pending transactions, and reversals

Idempotency keys where possible (stable source IDs or careful fingerprints). Handle duplicate Shortcut runs, repeated notifications, pending→posted updates, reversals, refunds, legitimate repeated purchases. Don't dedupe solely by amount + date if that could merge separate purchases.

### Transaction UI

Users can view/search/filter, open details, edit fields, change category/account, add notes, review automatic classifications, delete with clear confirmation or undo where feasible. Fix blank editors, blank category pickers, broken navigation. No controls that lead nowhere.

## 9. Ghaf AI

### Role and capabilities

Central financial assistant, connected to user's data. Not static chat UI with canned answers.

Build toward: Arabic + English conversation; natural-language financial questions; voice transaction entry; categorization suggestions; merchant + account recognition; spending/budget analysis; recurring spending detection; subscription awareness; period comparisons; useful reminders/explanations.

Example questions:
- "How much did I spend this week?"
- "Where did most of my money go?"
- "How much did I spend on restaurants this month?"
- "How much do I have across my accounts?"
- "Am I spending more than last month?"
- "Which subscriptions are due soon?"
- "كم صرفت هالأسبوع؟"
- "وين أكثر مكان صرفت فيه؟"
- "سجلت ٣٥ درهم غداء."

### Grounded financial answers

Numerical questions:
1. Retrieve relevant records.
2. Apply deterministic calculations.
3. Respect account + currency boundaries.
4. State period, explain result.
5. Never invent missing data.

LLM must not calculate authoritative balances from unverified prompt summary.

### Voice transaction entry

Support natural Arabic + English, e.g.:
- "I spent 35 dirhams on lunch."
- "Paid 120 AED for fuel using Mashreq."
- "اشتريت قهوة بعشرين درهم."
- "دفعت ٥٠ درهم بنزين."

Extract amount, currency, merchant/description, category, type, account if known, date if specified. Essential field unclear → concise clarification, no silent guess. Multiple purchases in one utterance → separate candidates. Confirm/review where necessary.

### Genuine learning

Learn from actual user actions + confirmed corrections: changing suggested category; changing merchant's account; editing merchant name; confirming/rejecting suggested transaction; repeated consistent category for merchant/pattern.

Store structured feedback: normalized merchant key; confirmed category; confirmed account mapping; user preference; confidence/count; last-confirmed timestamp; source + parser/model version.

Use learned data to improve suggestions. Prefer transparent deterministic mappings for repeated high-confidence corrections. Describe accurately whether capability is local preference/mapping, server-side retrieval memory, trained model, or recent-context suggestion. Don't claim model training if only local rule stored.

### Hybrid architecture and privacy

On-device where practical: local preferences, confirmed mappings, basic parsing/categorization, offline behavior, deterministic calculations. Secure backend for advanced cloud reasoning if needed.

- Never embed provider API keys/secrets in iOS binary.
- Check whether backend exists before proposing another; reuse infrastructure.
- Explain tradeoffs before new service.
- Minimize financial data shared; send only context needed for current task. Don't send full history every request by default.
- Authenticated requests, secure transport. Define retention + deletion.
- Controls to inspect, reset, disable learned preferences. Make AI data use understandable.

### AI interface

Clear starting point, useful suggested questions, voice/text input, readable conversation, clear distinction between answers, suggestions, transactions awaiting confirmation. Loading, error, empty, offline states. No fake thinking animations or fabricated responses.

## 10. Subscriptions

Dedicated tab, integrated with rest of Ghaf.

### Subscription data

Support: name; amount + currency; billing cycle; next payment date; category; payment account; reminder preference; notes; active/inactive; creation + update dates. Cycles: weekly, monthly, quarterly, yearly; design for extensibility.

### Overview

Show active subscriptions, upcoming dates, monthly equivalent cost, annual cost, payment history where available. Label estimated monthly equivalents for non-monthly cycles. Correct decimal arithmetic, no integer division.

### Reminders

- Local notifications where appropriate. Request permission with clear explanation.
- Reminder timing preferences. Reschedule on date/cycle/status change; cancel on delete/deactivate.
- Handle denied permission gracefully.
- Reminder ≠ proof of payment.

### Transaction matching

Compare ingested real transaction with active subscriptions using merchant, amount, date window, account evidence.
- Confidence thresholds; ask confirmation when uncertain.
- Record confirmed payments in history.
- Advance next payment date only after confirmed payment or clearly defined trusted rule.
- Prevent duplicate payment records + duplicate balance deductions.
- Reminder never deducts money. Only confirmed transaction affects ledger.

## 11. More screen and Profile

### More screen

Few clear groups:
- **Profile**: personal details; profile image or initials; language + personal preferences.
- **Accounts**: bank accounts + wallets.
- **Preferences**: currency; appearance; language; notifications.
- **Ghaf AI**: learning preferences; privacy controls; learned mappings/preferences; reset learning data.
- **Data**: import; export; backup/restore if supported.
- **About**: app info; help + support.

No long cluttered list of unrelated cards. Every row leads to working destination.

### Profile

Clear, well-designed profile screen with supported editable fields, consistent spacing + typography. Don't invent authentication or profile sync without backend.

## 12. Currencies and money formatting

Currency selector + display need correction.

### Dedicated artwork

Currency-specific artwork only for: UAE Dirham (AED); Saudi Riyal (SAR); Omani Rial (OMR). Remove generic currency icons + placeholders. No country flags. Other currencies: abbreviation as text.

### Formatting and calculations

- Keep currency codes + amounts paired correctly. Locale-aware number formatting.
- Avoid ambiguous shared symbols.
- Consistent formatting across accounts, transactions, subscriptions, summaries.
- Never aggregate currencies without real conversion rate; when converting, show rate + timestamp.
- Changing display currency must not silently change historical transaction currencies.

## 13. Arabic, English, and localization

Support Arabic + English throughout.
- Arabic: proper RTL. English: proper LTR.
- Semantic leading/trailing over hardcoded left/right. Handle directional icons.
- Don't manually reverse components if SwiftUI layout direction handles it.

Language switch must update navigation, headings, buttons, forms, empty states, categories, transaction types, dates, currency formatting, notifications, AI interface/prompts. No mixed-language UI except user-provided merchant names/notes. Check clipping + button widths in both languages.

## 14. Welcome screen and onboarding

Supplied welcome artwork = actual welcome screen. User wants it shown on every fresh launch after app fully removed from app switcher.
- Not same as restarting first-time onboarding.
- Don't erase data or reset accounts/preferences. Don't force full onboarding every launch.
- Returning from background ≠ fresh process launch.
- Verify asset catalog membership + target packaging. Verify actual launch behavior; `Image` reference alone doesn't prove asset packaged.

If iOS launch-screen restrictions apply, explain what native launch screen can do vs what needs in-app welcome view.

## 15. Import, export, and backup

Existing JSON import workflow must work.

### Import

- Select supported Ghaf JSON file. Validate schema/version before import.
- Understandable errors for invalid/unsupported files. Never silently do nothing.
- No partial imports leaving inconsistent data. Handle duplicate imports safely where possible.
- Preserve accounts, transactions, categories, settings, subscriptions, relevant preferences.

### Export

- Export data supported by current schema. Versioned, documented format.
- No unnecessary secrets. State clearly what's included/excluded.

Add schema/version handling as models evolve. Don't claim compatibility with untested formats.

## 16. Notifications and Shortcuts

Notifications useful, accurate, user-controlled. Distinguish transaction review, subscription reminders, budget alerts, optional financial reminders.
- No duplicate notifications for same event. Appropriate settings. Handle denied permission gracefully.
- Shortcut setup understandable. Clear App Intent names + parameters.
- Validate incoming data. Return useful success/failure results. Ingestion idempotent.
- No manual app navigation required per transaction.
