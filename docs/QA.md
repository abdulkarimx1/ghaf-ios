# Ghaf QA checklist

> Moved from CLAUDE.md §17. Read before release or QA work.


Use for relevant changes. Don't mark passed unless actually performed.

### Navigation and UI
- [ ] Five tabs in intended order.
- [ ] Ghaf AI is center tab.
- [ ] Every tab opens functional screen.
- [ ] Home has no long transaction feed.
- [ ] Daily/Weekly/Monthly updates real data.
- [ ] Hidden balances use star representation.
- [ ] More simplified + navigable.
- [ ] Profile actions work.
- [ ] No blank editor or category screens.
- [ ] No clipped content or safe-area overlap.

### Accounts and ledger
- [ ] Multiple accounts supported.
- [ ] No empty accounts created automatically.
- [ ] Each transaction affects correct account exactly once.
- [ ] Transfers don't inflate income/spending.
- [ ] Refunds + reversals handled distinctly.
- [ ] Different currencies not incorrectly added.
- [ ] Balances persist after relaunch.

### Transactions and automation
- [ ] Arabic + English parsing tested.
- [ ] Multiple purchases stay separate.
- [ ] OTP/promotional messages don't create transactions.
- [ ] Duplicate Shortcut runs don't duplicate records.
- [ ] Account matching uses evidence.
- [ ] Low-confidence transactions go to review.
- [ ] Editing + category changes work.
- [ ] JSON import works + reports errors.

### Ghaf AI
- [ ] Numerical answers use actual ledger data.
- [ ] AI doesn't invent balances or transactions.
- [ ] Arabic/English voice entry works where supported.
- [ ] Confirmed corrections influence future suggestions.
- [ ] Learning behavior accurately described.
- [ ] No API secrets in app bundle.
- [ ] Privacy/reset controls work.

### Subscriptions
- [ ] Add/edit/delete works.
- [ ] Billing cycle calculations correct.
- [ ] Reminders schedule + reschedule.
- [ ] Deactivated subscriptions stop reminders.
- [ ] Confirmed payments match without double-counting.
- [ ] Payment history preserved.
- [ ] Reminders don't deduct balances.

### Localization and launch
- [ ] Arabic RTL works.
- [ ] English LTR works.
- [ ] Language switch updates whole UI.
- [ ] AED, SAR, OMR artwork correct.
- [ ] Other currencies use text abbreviations.
- [ ] Welcome artwork packaged.
- [ ] Fresh-process launch behavior correct.
- [ ] Existing data survives launch + updates.
