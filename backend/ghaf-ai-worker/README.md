# Ghaf AI server (Cloudflare Worker)

The one server every copy of Ghaf uses for the optional Cloud AI. The developer deploys it once;
users only turn Cloud AI on in the app. Live at `https://ghaf-ai.ghafapp.workers.dev` (the address
is built into `GhafCloudAI.endpoint`).

## How it works

- **Models:** Google Gemini (`GEMINI_MODEL`, default `gemini-flash-latest`, then
  `gemini-flash-lite-latest` when busy). If Gemini refuses the request (some Cloudflare locations
  are not supported by the Gemini API, quota, overload), it answers with Cloudflare Workers AI
  (`FALLBACK_MODEL`, default Gemma 4 26B) — free daily allowance, no key.
- **No secret in the app:** each install sends a random device ID (`X-Ghaf-Device`, kept in the
  iPhone's Keychain). The Worker allows `FREE_DAILY_LIMIT` questions per device per day and
  `GLOBAL_DAILY_LIMIT` in total, counted in the `USAGE` KV namespace (keys expire after two days).
  Over the limit it returns 429 and Ghaf answers on the device. On the free tiers the worst case
  is reaching a limit, not a bill.
- **Developer bypass:** requests with the `APP_TOKEN` secret in `X-Ghaf-Token` skip the limits
  (for testing from a Mac; never put it in the app).
- **Received:** the question, totals-only facts, the ledger's own answer and the last few chat
  lines. **Not received:** the transaction list, notes, card or account numbers. **Stored:** only
  the daily counters. Google's Gemini API terms apply to requests it handles.

## Later: paid plan

When Ghaf adds in-app purchases, Pro installs will send their StoreKit 2 signed transaction; the
Worker verifies Apple's signature and applies a higher daily limit. App Attest (needs a signed
build) can then confirm requests come from the genuine app.

## Deploy or update

First time on a new Mac or account, run `./setup.sh` (signs in, sets secrets, deploys). To ship a
change to `worker.js` or `wrangler.toml`:

```bash
npx wrangler@4 deploy
```
