#!/bin/zsh
# Setup for the Ghaf AI Worker; safe to run again. Run it yourself: it signs you in to Cloudflare
# (once), sets a fresh random access token, asks for your Gemini API key only if none is stored
# (https://aistudio.google.com/apikey), deploys, and prints what to enter in Ghaf
# (More > What Ghaf learned > Cloud AI). A new Cloudflare account is asked to pick a
# workers.dev subdomain during the deploy.
set -euo pipefail
cd "$(dirname "$0")"
wrangler=(npx --yes wrangler@4)

$wrangler whoami 2>/dev/null | grep -q "You are logged in" || $wrangler login

token=$(openssl rand -hex 24)
print -n "$token" | $wrangler secret put APP_TOKEN
echo "Access token for Ghaf (also shown at the end): $token"

if ! $wrangler secret list 2>/dev/null | grep -q GEMINI_API_KEY; then
  echo "Paste your Gemini API key when asked:"
  $wrangler secret put GEMINI_API_KEY
fi

# Interactive on purpose: a new account is offered a workers.dev subdomain here.
$wrangler deploy

echo
echo "Enter these in Ghaf > More > What Ghaf learned > Cloud AI:"
echo "  Server URL:   the https://ghaf-ai.<subdomain>.workers.dev address printed above"
echo "  Access token: $token"
