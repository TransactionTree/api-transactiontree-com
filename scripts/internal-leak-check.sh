#!/usr/bin/env bash
# internal-leak-check.sh — scan a file for content that must not be published in
# api.transactiontree.com. Exits non-zero on any hit.
#
# Used in CI (.github/workflows/pr-checks.yml and publish-to-postman.yml) and
# runnable locally:
#   scripts/internal-leak-check.sh postman/collection.json
#
# gitleaks handles generic secret patterns separately. What lives here are
# TT-specific facts gitleaks doesn't know about. Findings are printed MASKED
# (first 3 chars + length) because CI logs on this public repo are public.

set -u

TARGET="${1:-postman/collection.json}"

if [[ ! -f "$TARGET" ]]; then
  echo "internal-leak-check: file not found: $TARGET" >&2
  exit 2
fi

hits=0

mask() {
  awk '{ printf "    %s…(%d)\n", substr($0, 1, 3), length($0) }'
}

report() {
  local label="$1"
  local matches="$2"
  if [[ -n "$matches" ]]; then
    echo "FAIL — $label: $(echo "$matches" | wc -l) distinct"
    echo "$matches" | mask
    hits=$((hits + 1))
  fi
}

# scan LABEL ERE-PATTERN  (case-insensitive)
scan() {
  report "$1" "$(grep -oiE "$2" "$TARGET" | sort -u || true)"
}

# scan_pcre LABEL PCRE-PATTERN [EXCLUDE-ERE]
scan_pcre() {
  local matches
  matches=$(grep -oP "$2" "$TARGET" | sort -u || true)
  if [[ -n "${3:-}" && -n "$matches" ]]; then
    matches=$(echo "$matches" | grep -viE "$3" || true)
  fi
  report "$1" "$matches"
}

# --- infrastructure -------------------------------------------------------------------
scan "internal IPv4 (RFC1918 + TT Flexential /27)" \
  '(\b10\.0\.0\.[0-9]{1,3}\b|\b10\.10\.0\.[0-9]{1,3}\b|\b192\.168\.[0-9]{1,3}\.[0-9]{1,3}\b|\b128\.136\.200\.[0-9]{1,3}\b|\b208\.93\.113\.[0-9]{1,3}\b)'

scan "internal-only hostnames" \
  '\b([a-z0-9-]+\.)?(lynxs\.local|lynxs\.cloud|lynxs\.network|bormc\.io)\b'

scan "TT environment hosts (use a {{...URL}} variable or sandbox.example.com)" \
  '\b[a-z0-9_-]+\.(receiptx\.com|bormc\.com|storesmail\.com)\b'

scan "BORMC admin paths" \
  '/(webtools|webtools-test|accounting|partymgr|workeffort|content)/control/'

# --- credentials ----------------------------------------------------------------------
scan "known stale credentials (audit 2026-05-28)" \
  '(peterparker|pparkertt33)'

scan "literal VRG sectoken in a URL" \
  'sectoken=[A-Za-z0-9+/=%_-]{16,}'

# Postman key/value pairs (headers, query params, variables) span lines, so use jq.
# An empty value, a {{variable}} or a <placeholder> passes.
report "literal credential in a key/value pair (use {{variable}} or <string>)" "$(
  jq -r '[.. | objects | select(has("key") and has("value"))]
         | map(select((.key | tostring | test("^(sectoken|accessTokenKey|X-tenant-Key|access_token|client_password|[a-z_]*pass(word)?)$"; "i"))
                      and (.value | tostring | test("^(\\{\\{|<|$)") | not)))
         | .[].value' "$TARGET" 2>/dev/null | sort -u
)"

scan "recorded session cookies" \
  'JSESSIONID=0*[1-9A-F][0-9A-F]{7,}'

# --- customers & people ---------------------------------------------------------------
scan "customer-identifying names / hosts" \
  '(princess ?auto|princessauto\.com|spencers?\b|scene7\.com|arc ?thrift|citi ?trends|harmons|worldwide golf|lowes foods|alex lee|bass pro|cabela)'

# Emails: only placeholder domains plus the documented validation fixtures
scan_pcre "email outside placeholder domains" \
  '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
  '@example\.(com|org|net)$|^(support@transactiontree\.com|email@email\.com|example@donotuse\.com|example@agoodmail\.com|123@gmail\.com|customer@gmail\.com|customer@gamil\.com|do_not_email@icloud\.com)$'

# NANP phone numbers outside the reserved fictional 555-0100..0199 range
scan_pcre "phone number outside 555-01xx" \
  '(?<![0-9A-Za-z_-])(?:\+?1[-. ]?)?\(?[2-9]\d{2}\)?[-. ]?[2-9]\d{2}[-. ]\d{4}(?![0-9A-Za-z_-])|(?<![0-9A-Za-z_-])\+?1?[2-9]\d{2}[2-9]\d{6}(?![0-9A-Za-z_-])' \
  '555[-. )]*01[0-9]{2}$'

if [[ $hits -gt 0 ]]; then
  echo
  echo "internal-leak-check: $hits class(es) of finding — fix before publishing."
  exit 1
fi

echo "internal-leak-check: clean — $TARGET passed all scans."
exit 0
