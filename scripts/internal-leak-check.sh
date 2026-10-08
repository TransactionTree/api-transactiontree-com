#!/usr/bin/env bash
# internal-leak-check.sh — scan a file (or stdin) for content that must not be
# published in api.transactiontree.com. Exits non-zero on any hit.
#
# Used in CI (.github/workflows/internal-leak-scan.yml) and runnable locally:
#   scripts/internal-leak-check.sh postman/collection.json
#
# This is a coarse filter — gitleaks handles generic secret patterns separately.
# What lives here are TT-specific facts the gitleaks ruleset doesn't know about.

set -u

TARGET="${1:-postman/collection.json}"

if [[ ! -f "$TARGET" ]]; then
  echo "internal-leak-check: file not found: $TARGET" >&2
  exit 2
fi

hits=0

scan() {
  local label="$1"
  local pattern="$2"
  local matches
  matches=$(grep -oiE "$pattern" "$TARGET" | sort -u || true)
  if [[ -n "$matches" ]]; then
    echo "FAIL — $label:"
    echo "$matches" | sed 's/^/    /'
    hits=$((hits + 1))
  fi
}

# Internal IP ranges
scan "internal IPv4 (RFC1918 + TT Flexential /27)" \
  '(\b10\.0\.0\.[0-9]{1,3}\b|\b10\.10\.0\.[0-9]{1,3}\b|\b192\.168\.[0-9]{1,3}\.[0-9]{1,3}\b|\b128\.136\.200\.[0-9]{1,3}\b|\b208\.93\.113\.[0-9]{1,3}\b)'

# Internal hostnames — anything that resolves only inside TT or the customer network
scan "internal-only hostnames" \
  '\b([a-z0-9-]+\.)?(lynxs\.local|lynxs\.cloud|lynxs\.network|bormc\.io)\b'

# Admin paths on bormc.com that should never appear in customer docs
scan "BORMC admin paths" \
  '/(webtools|webtools-test|accounting|partymgr|workeffort|content)/control/'

# Known stale credentials from the initial mirror (scrubbed) -- must never return
scan "known stale credentials (audit 2026-05-28)" \
  '(peterparker|pparkertt33)'

# Literal VRG security tokens -- examples must use the {{sectoken}} variable
scan "literal VRG sectoken" \
  'sectoken=[A-Za-z0-9+/=%_-]{16,}'

# Customer branding / hosts that must not appear in public examples
scan "customer-identifying hosts" \
  '\b(princessauto\.com|spencers\.scene7\.com|storesmail\.com|sandbox_(arcthrift|harmons|princess|cititrends|rona|wnp|wwg|spencer)[a-z]*\.receiptx\.com|devtest\.receiptx\.com)\b'

# Recorded session cookies
scan "recorded session cookies" \
  'JSESSIONID=0*[1-9A-F][0-9A-F]{7,}'

# Example email addresses must use placeholder domains (warn-only)
if grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}' "$TARGET" | grep -viE '@(example\.(com|org|net)|domain\.com|email\.com|gamil\.com|transctiontree\.com)$|^support@transactiontree\.com$' | grep -q .; then
  echo "WARN — email addresses outside placeholder domains (manual review needed):"
  grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}' "$TARGET" | grep -viE '@(example\.(com|org|net)|domain\.com|email\.com|gamil\.com|transctiontree\.com)$|^support@transactiontree\.com$' | sort -u | sed 's/^/    /'
fi

# Generic password fields with non-placeholder values
# (matches "password":"..." but allows obvious placeholders)
if grep -oE '"[Pp]assword"\s*:\s*"[^"<{$][^"]{4,}"' "$TARGET" >/dev/null; then
  echo "WARN — non-placeholder values in password fields (manual review needed):"
  grep -oE '"[Pp]assword"\s*:\s*"[^"]{1,40}"' "$TARGET" | sort -u | sed 's/^/    /'
  # Warn-only — gitleaks owns the hard fail on real-looking secrets
fi

if [[ $hits -gt 0 ]]; then
  echo
  echo "internal-leak-check: $hits class(es) of finding — fix before publishing."
  exit 1
fi

echo "internal-leak-check: clean — $TARGET passed all scans."
exit 0
