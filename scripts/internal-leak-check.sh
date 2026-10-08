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

# A missing tool must fail the check, never let it pass silently.
command -v jq >/dev/null || { echo "internal-leak-check: jq is required" >&2; exit 2; }
echo x | grep -qP 'x' 2>/dev/null || { echo "internal-leak-check: grep -P (PCRE) is required" >&2; exit 2; }
jq -e . "$TARGET" >/dev/null 2>&1 || { echo "internal-leak-check: $TARGET is not valid JSON" >&2; exit 2; }

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

# scan_jq LABEL JQ-FILTER  (filter emits offending strings; jq failure = FAIL)
scan_jq() {
  local out
  if ! out=$(jq -r "$2" "$TARGET"); then
    report "$1 (jq filter failed)" "jq-error"
    return
  fi
  report "$1" "$(echo "$out" | sed '/^$/d' | sort -u)"
}

# A value is a placeholder if it is empty, a <placeholder>, or contains {{variable}}.
NOT_PLACEHOLDER='(tostring | test("^$|^<|\\{\\{") | not)'

# --- infrastructure -------------------------------------------------------------------
scan "private / TT IPv4" \
  '(\b10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b|\b172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}\b|\b192\.168\.[0-9]{1,3}\.[0-9]{1,3}\b|\b128\.136\.200\.[0-9]{1,3}\b|\b208\.93\.113\.[0-9]{1,3}\b)'

scan "internal-only hostnames" \
  '\b([a-z0-9-]+\.)?(lynxs\.local|lynxs\.cloud|lynxs\.network|bormc\.io)\b'

scan "TT environment hosts (use a {{...URL}} variable or sandbox.example.com)" \
  '\b[a-z0-9_-]+\.(receiptx\.com|bormc\.com|storesmail\.com)\b'

scan "BORMC admin paths" \
  '/(webtools|webtools-test|accounting|partymgr|workeffort|content)/control/'

scan "local file paths" \
  '([A-Z]:/Users/|[A-Z]:\\\\Users\\\\|/home/[a-z0-9_-]+/)'

# --- credentials ----------------------------------------------------------------------
scan "known stale credentials (audit 2026-05-28)" \
  '(peterparker|pparkertt33)'

scan "literal VRG sectoken in a URL" \
  'sectoken=[A-Za-z0-9+/=%_-]{16,}'

# Postman key/value pairs (headers, query params, variables) span lines, so use jq.
scan_jq "literal credential in a key/value pair (use {{variable}} or <string>)" \
  "[.. | objects | select(has(\"key\") and has(\"value\"))
    | select((.key | tostring | test(\"^(sectoken|accessTokenKey|X-tenant-Key|access_token|client_password|client_secret|authorization|cookie|token|api_?key|[a-z_]*pass(word)?)\$\"; \"i\")) and (.value | $NOT_PLACEHOLDER))
    | .value] | .[] | tostring"

# Auth blocks store the secret under key value/token/password (e.g. apikey/bearer/basic).
scan_jq "literal credential in an auth block" \
  "[.. | objects | select(has(\"auth\")) | .auth | objects | to_entries[] | select(.key != \"type\") | .value | arrays | .[]
    | select((.key | tostring | test(\"^(value|token|password|username)\$\")) and (.value | $NOT_PLACEHOLDER))
    | .value] | .[] | tostring"

scan "recorded session cookies" \
  'JSESSIONID=0*[1-9A-F][0-9A-F]{7,}'

# --- customers & people ---------------------------------------------------------------
scan "customer-identifying names / hosts" \
  '(princess ?auto|princessauto\.com|\bPAL\b|spencers?\b|scene7\.com|arc ?thrift|citi ?trends|harmons|worldwide golf|lowes foods|alex lee|bass pro|cabela|\bhertz\b|\brona\b|\bwnp\b|western national|eastside sports|\bmuji\b|crazy shirts)'

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
