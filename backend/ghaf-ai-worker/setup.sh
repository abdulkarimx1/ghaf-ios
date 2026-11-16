#!/bin/zsh
# One-time setup for the Ghaf AI Worker. Run it yourself: it signs you in to Cloudflare, creates a
# random access token, asks you to paste your Gemini API key (https://aistudio.google.com/apikey),
# deploys, and prints the two values to enter in Ghaf (More > What Ghaf learned > Cloud AI).
set -euo pipefail
cd "$(dirname "$0")"

npx --yes wrangler@4 login

token=$(openssl rand -hex 24)
print -n "$token" | npx --yes wrangler@4 secret put APP_TOKEN
echo "Paste your Gemini API key when asked:"
npx --yes wrangler@4 secret put GEMINI_API_KEY

npx --yes wrangler@4 deploy | tee deploy.log
url=$(grep -Eo 'https://[a-zA-Z0-9.-]+\.workers\.dev' deploy.log | head -1)
rm -f deploy.log

echo
echo "Enter these in Ghaf > More > What Ghaf learned > Cloud AI:"
echo "  Server URL:   $url"
echo "  Access token: $token"
