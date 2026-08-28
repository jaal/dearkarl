#!/usr/bin/env bash
# Deploy the dearkarl email Worker via the raw Cloudflare API (no wrangler/Node).
#
# Required env:
#   CLOUDFLARE_API_TOKEN  — scopes: Account:Workers Scripts:Edit,
#                           Zone:Zone:Read, Zone:Email Routing Rules:Edit
# Optional env:
#   GITHUB_TOKEN_FOR_WORKER — fine-grained PAT (Contents:RW on the inbox repo
#                             ONLY). Omit to deploy in log-only mode.
#   SEND_TO_ADDRESS         — full secret address; generated if unset.
#   AUTH_ENFORCE            — "1" rejects mail whose From: header fails DMARC.
#                             Leave unset on a first install: watch
#                             `grep auth_check inbox/*.md` until every address
#                             you send from reads "pass", then set it and
#                             re-upload. Enforcing blind locks you out.
#
# Usage: ./deploy.sh   (from the worker/ directory)
set -euo pipefail

: "${CLOUDFLARE_API_TOKEN:?set CLOUDFLARE_API_TOKEN first (scopes above)}"

# Your config — all required except SCRIPT_NAME:
ZONE_NAME="${ZONE_NAME:?set ZONE_NAME (your Cloudflare zone, e.g. example.com)}"
SCRIPT_NAME="${SCRIPT_NAME:-dearkarl-email}"
GITHUB_REPO="${GITHUB_REPO:?set GITHUB_REPO (owner/your-private-inbox-repo)}"
ALLOWED_SENDERS="${ALLOWED_SENDERS:?set ALLOWED_SENDERS (comma-separated sender emails)}"

api() { # method path [json-body]
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -sS -X "$method" "https://api.cloudflare.com/client/v4$path" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" --data "$body"
  else
    curl -sS -X "$method" "https://api.cloudflare.com/client/v4$path" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"
  fi
}

jqget() { /usr/bin/python3 -c "import sys,json;d=json.load(sys.stdin);print(eval(sys.argv[1]))" "$1"; }

echo "== Resolving account and zone =="
ACCOUNT_ID=$(api GET "/accounts?per_page=1" | jqget "d['result'][0]['id']")
ZONE_JSON=$(api GET "/zones?name=$ZONE_NAME")
ZONE_ID=$(echo "$ZONE_JSON" | jqget "d['result'][0]['id']")
echo "account=$ACCOUNT_ID zone=$ZONE_ID ($ZONE_NAME)"

echo "== Checking existing MX records (Email Routing will replace them) =="
MX_COUNT=$(api GET "/zones/$ZONE_ID/dns_records?type=MX" | jqget "len(d['result'])")
if [ "$MX_COUNT" != "0" ]; then
  echo "!! $ZONE_NAME already has $MX_COUNT MX record(s) — it receives mail somewhere."
  echo "!! Enabling Email Routing would take over mail for the whole domain. STOPPING."
  echo "!! Inspect: dash.cloudflare.com -> $ZONE_NAME -> DNS -> records (type MX)"
  exit 1
fi
echo "no MX records — safe to enable Email Routing."

echo "== Uploading worker script =="
BINDINGS='[{"type":"plain_text","name":"ALLOWED_SENDERS","text":"'"$ALLOWED_SENDERS"'"},{"type":"plain_text","name":"GITHUB_REPO","text":"'"$GITHUB_REPO"'"}'
if [ -n "${AUTH_ENFORCE:-}" ]; then
  BINDINGS+=',{"type":"plain_text","name":"AUTH_ENFORCE","text":"'"$AUTH_ENFORCE"'"}'
  echo "(AUTH_ENFORCE=$AUTH_ENFORCE — DMARC failures will be rejected)"
else
  echo "(no AUTH_ENFORCE — DMARC verdicts logged only, mail delivered)"
fi
if [ -n "${GITHUB_TOKEN_FOR_WORKER:-}" ]; then
  BINDINGS+=',{"type":"secret_text","name":"GITHUB_TOKEN","text":"'"$GITHUB_TOKEN_FOR_WORKER"'"}'
  echo "(with GITHUB_TOKEN secret — commit mode)"
else
  echo "(no GITHUB_TOKEN_FOR_WORKER — log-only mode)"
fi
BINDINGS+=']'
# Pin filename= to the full module path; curl otherwise defaults it to the
# basename, so imports like "./vendor/postal-mime/postal-mime.js" fail to
# resolve and Cloudflare rejects the upload ("No such module").
MODULE_PARTS=(-F "worker.js=@worker.js;filename=worker.js;type=application/javascript+module")
for mod in vendor/postal-mime/*.js; do
  MODULE_PARTS+=(-F "$mod=@$mod;filename=$mod;type=application/javascript+module")
done
curl -sS -X PUT \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/scripts/$SCRIPT_NAME" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -F 'metadata={"main_module":"worker.js","compatibility_date":"2026-07-01","bindings":'"$BINDINGS"'};type=application/json' \
  "${MODULE_PARTS[@]}" \
  | jqget "'upload ok' if d['success'] else d['errors']"

echo "== Enabling Email Routing on the zone =="
api POST "/zones/$ZONE_ID/email/routing/enable" "" \
  | jqget "'enabled' if d.get('success') else d.get('errors')" \
  || echo "(if this failed, enable in dashboard: $ZONE_NAME -> Email -> Email Routing)"

echo "== Creating the secret address route =="
if [ -z "${SEND_TO_ADDRESS:-}" ]; then
  SUFFIX=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 8)
  SEND_TO_ADDRESS="karl-${SUFFIX}@${ZONE_NAME}"
fi
api POST "/zones/$ZONE_ID/email/routing/rules" '{
  "name": "dearkarl inbox",
  "enabled": true,
  "matchers": [{"type": "literal", "field": "to", "value": "'"$SEND_TO_ADDRESS"'"}],
  "actions": [{"type": "worker", "value": ["'"$SCRIPT_NAME"'"]}]
}' | jqget "'route ok' if d['success'] else d['errors']"

echo
echo "DONE. Your secret address: $SEND_TO_ADDRESS"
echo "Save it somewhere private — it is the only copy printed."
echo "Test: email it, then check github.com/$GITHUB_REPO -> inbox/ (or Worker logs in log-only mode)."
