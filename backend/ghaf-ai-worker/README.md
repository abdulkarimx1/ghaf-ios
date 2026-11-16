# Ghaf AI cloud proxy (optional)

A tiny Cloudflare Worker that lets Ghaf use Google Gemini's free tier without putting an API key
in the app. It is **off by default** in Ghaf; nothing is sent until you turn on Cloud AI in
More › What Ghaf learned and enter this Worker's URL and your access token.

## What it receives and keeps

- Receives: your question, a short summary of totals Ghaf computed (account balances, spending by
  period and category, upcoming subscriptions), the ledger's own answer if it has one, and the
  last few chat lines. Not sent: your transaction list, card or account numbers, notes.
- Keeps: nothing. The Worker stores no data. Google's Gemini API terms apply to the request; on the
  free tier Google may use prompts to improve its products, so use the paid tier if that matters.

## Deploy (about 5 minutes, free)

1. Create a Gemini API key at <https://aistudio.google.com/apikey>.
2. Install Wrangler and sign in to Cloudflare:

   ```bash
   npm install -g wrangler
   ```

   ```bash
   wrangler login
   ```

3. From this folder, set the two secrets (pick any long random string as the access token):

   ```bash
   wrangler secret put GEMINI_API_KEY
   ```

   ```bash
   wrangler secret put APP_TOKEN
   ```

4. Deploy:

   ```bash
   wrangler deploy
   ```

5. In Ghaf: More › What Ghaf learned › Cloud AI. Paste the URL Wrangler printed
   (for example `https://ghaf-ai.<you>.workers.dev`) and the same access token, then turn it on.

## Limits

- Gemini free-tier quotas apply. When the Worker or Gemini fails, Ghaf falls back to its on-device
  answers, so the numbers are always available.
- Change the model with the `GEMINI_MODEL` variable in `wrangler.toml`.
