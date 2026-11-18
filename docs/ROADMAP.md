# Ghaf implementation roadmap

> Moved from CLAUDE.md §18. Read when planning stages.


No massive all-at-once rewrite. Focused stages.

### Stage 1 — Inspect and stabilize
Inspect repo, branch, build config, latest CI. Find compile errors + broken flows. Fix persistence + navigation, blank transaction/category screens, language switching + safe-area problems, multi-account + balance inconsistencies. Verify welcome asset + launch behavior.

### Stage 2 — Core UI
Refine shared design system. Redesign Home around balances + overview; remove Home feed. Daily/Weekly/Monthly interaction. Hidden-balance stars. Simplify More, improve Profile. Confirm five tabs with Ghaf AI centered.

### Stage 3 — Accounts and transaction reliability
Fix account lifecycle + matching. Improve ingestion + duplicate prevention. Improve Arabic/English parsing. Fix voice transaction splitting + merchant cleanup. Complete transaction editing + review. Repair JSON import/export.

### Stage 4 — Subscriptions
Complete subscription CRUD + persistence. Reminders. Payment history. Confirmed transaction matching. Subscription statistics.

### Stage 5 — Ghaf AI
Complete AI interface. Voice input. Deterministic financial query tools. Secure backend if required. Confirmed-feedback learning. Privacy, inspection, reset controls.

### Stage 6 — QA and delivery
Run relevant automated tests. Full build. Check GitHub Actions; fix build failures. IPA only after successful build. Report what is/isn't verified. Don't imply physical-device testing unless performed.
