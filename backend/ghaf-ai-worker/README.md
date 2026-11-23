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
  iPhone's Keychain). The Worker returns `429 {code: "pro_required"}` for free-tier chat, speech,
  voice-turn, and Live token requests. Voice replies are counted in the `USAGE` KV namespace:
  `ESSENTIALS_DAILY_VOICE_LIMIT` defaults to 3 and `COMPLETE_DAILY_VOICE_LIMIT` defaults to 10.
  `FREE_DAILY_LIMIT` defaults to 0. The existing text quotas still apply to paid tiers.
- **Developer bypass:** requests with the `APP_TOKEN` secret in `X-Ghaf-Token` skip the limits
  (for testing from a Mac; never put it in the app).
- **Received:** the question, totals-only facts (including saved memories when enabled), the ledger's own answer and the last few chat
  lines. **Not received:** the transaction list, notes, card or account numbers. **Stored:** only
  the daily counters. Google's Gemini API terms apply to requests it handles.

`POST /live-token` mints a short-lived, single-use Gemini Live token and refuses free-tier callers.
`POST /voice-turn` and `/speak` share the tier's daily voice-reply counter. Live tokens retain the
app's setup through the field mask. Hamad uses `Orus`, Mariam uses `Kore`; these are Worker vars.
`GEMINI_API_KEY` remains a Worker secret.

## StoreKit verification status

The app checks a verified StoreKit entitlement locally, then sends the corresponding tier string.
The Worker cannot verify that client-claimed tier until App Store server verification is added.

## Deploy or update

First time on a new Mac or account, run `./setup.sh` (signs in, sets secrets, deploys). To ship a
change to `worker.js` or `wrangler.toml`:

```bash
npx wrangler@4 deploy
```
