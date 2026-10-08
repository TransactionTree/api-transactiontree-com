#!/usr/bin/env bash
# internal-leak-check.sh — scan a file for content that must not be published in
# api.transactiontree.com. Exits 1 on any finding, 2 if the scan itself cannot run.
#
# Used in CI (.github/workflows/pr-checks.yml and publish-to-postman.yml) and
# runnable locally (needs bash, jq and GNU grep with -P):
#   scripts/internal-leak-check.sh postman/collection.json
#
# This is the primary guard; gitleaks adds generic secret patterns on top.
# Findings are printed MASKED (first 3 chars + length) because CI logs on this
# public repo are public. It fails closed: a scanner error is a finding.

set -u

TARGET="${1:-postman/collection.json}"

if [[ ! -f "$TARGET" ]]; then
  echo "internal-leak-check: file not found: $TARGET" >&2
  exit 2
fi
command -v jq >/dev/null || { echo "internal-leak-check: jq is required" >&2; exit 2; }
echo x | grep -qP 'x' 2>/dev/null || { echo "internal-leak-check: GNU grep with -P (PCRE) is required" >&2; exit 2; }
jq -e . "$TARGET" >/dev/null 2>&1 || { echo "internal-leak-check: $TARGET is not valid JSON" >&2; exit 2; }

hits=0

# Show at most 3 leading chars, and only when the value is long enough (>= 9) that
# they reveal little; shorter values are fully redacted. Length is always shown.
mask() {
  awk '{ n = length($0); printf "    %s…(%d)\n", (n >= 9 ? substr($0, 1, 3) : "***"), n }'
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

# run_grep FLAGS PATTERN -> matches on stdout; grep status 1 (no match) is fine, >1 is an error
run_grep() {
  local out rc
  out=$(grep "$1" -- "$2" "$TARGET")
  rc=$?
  if [[ $rc -gt 1 ]]; then
    echo "__SCANNER_ERROR__"
    return
  fi
  [[ -n "$out" ]] && echo "$out" | sort -u
}

# scan LABEL PCRE [EXCLUDE-ERE]   (case-insensitive)
scan() {
  local matches
  matches=$(run_grep -oiP "$2")
  if [[ "$matches" == *__SCANNER_ERROR__* ]]; then
    report "$1 (scanner error)" "grep-error"
    return
  fi
  if [[ -n "${3:-}" && -n "$matches" ]]; then
    matches=$(echo "$matches" | grep -viE "$3" || true)
  fi
  report "$1" "$matches"
}

# scan_jq LABEL JQ-FILTER  (filter emits offending strings; a jq failure is a finding)
scan_jq() {
  local out
  if ! out=$(jq -r "$2" "$TARGET"); then
    report "$1 (jq filter failed)" "jq-error"
    return
  fi
  report "$1" "$(echo "$out" | sed '/^$/d' | sort -u)"
}

# A placeholder is empty, a whole <placeholder>, a whole {{variable}}, or "Basic/Bearer {{variable}}".
PLACEHOLDER='test("^$|^<[^<>]+>$|^\\{\\{[^{}]+\\}\\}$|^(Basic|Bearer) \\{\\{[^{}]+\\}\\}$")'
# Same idea inside free text (PCRE negative lookahead body). A placeholder only counts if
# the field ends right after it, so "<secret-value" or "<string>literal" are not exempt.
PH='(\{\{[^{}]+\}\}|<[^<>]+>|&lt;[^&]+&gt;)(?=$|["&\\<;])'

# --- infrastructure -------------------------------------------------------------------
scan "private / TT / CGNAT IPv4" \
  '\b(10\.\d{1,3}|172\.(1[6-9]|2\d|3[01])|192\.168|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7]))\.\d{1,3}\.\d{1,3}\b|\b(128\.136\.200|208\.93\.113)\.\d{1,3}\b'

scan "internal-only hostnames" \
  '\b([a-z0-9-]+\.)?(lynxs\.local|lynxs\.cloud|lynxs\.network|bormc\.io)\b'

scan "TT environment hosts (use a {{...URL}} variable or sandbox.example.com)" \
  '\b([a-z0-9_-]+\.)*(receiptx\.com|bormc\.com|storesmail\.com|digivize\.ai|vrgs\.io|cust360\.ai|ltschat\.com)\b|\b(?!www\.|api\.)[a-z0-9_-]+\.transactiontree\.com\b'

# Postman also stores hosts split into arrays ("ptest1","storesmail","com"), which text scans miss.
scan_jq "TT / internal host in a url.host array" \
  '[.. | objects | select(has("host") and (.host | type == "array")) | .host | map(tostring) | join(".")
    | select(test("(receiptx|bormc|storesmail|ltschat)\\.com|digivize\\.ai|vrgs\\.io|cust360\\.ai|lynxs\\.|bormc\\.io|^(10|192\\.168|172\\.(1[6-9]|2[0-9]|3[01])|100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])|128\\.136\\.200|208\\.93\\.113)\\.|(^|\\.)(?!www\\.|api\\.)[a-z0-9_-]+\\.transactiontree\\.com$"; "i"))] | .[]'

scan "BORMC admin paths" \
  '/(webtools|webtools-test|accounting|partymgr|workeffort|content)/control/'

scan "local file paths" \
  '([A-Z]:/Users/|[A-Z]:\\\\Users\\\\|/home/[a-z0-9_-]+/|(?<![A-Za-z0-9/])/Users/[A-Za-z0-9._-]+/)'

# --- credentials ----------------------------------------------------------------------
scan "known stale credentials (audit 2026-05-28)" \
  '(peterparker|pparkertt33)'

scan "literal VRG sectoken in a URL" \
  'sectoken=(?!'"$PH"')[A-Za-z0-9+/=%_-]{8,}'

scan "literal username / password in a URL" \
  '[?&][a-z_]*(password|username)=(?!'"$PH"')[^&"\\\s]+'

# Any non-placeholder value after a credential key in a body (JSON, XML or query style)
scan "literal credential inside a body string" \
  '(access_?token(key)?|sectoken|client_?(secret|password)|api[_-]?key|x-tenant-key|x-auth-token|subscription-key|password|\btoken)(\\?"\s*:\s*\\?"|&gt;|>|=)(?!'"$PH"'|\\?"|</|&lt;/)(&lt;|<)?[^"\\<&\s]{4,}'

CRED_KEYS='^(sectoken|accessTokenKey|X-tenant-Key|access_?token|accessToken|refresh_?token|token|x-auth-token|.*subscription-key|client_?secret|clientSecret|client_?password|secret|authorization|cookie|username|.*api[-_]?key|[a-z_]*pass(word)?)$'

# Postman key/value pairs (headers, query params, variables) span lines, so use jq.
scan_jq "literal credential in a key/value pair (use {{variable}} or <string>)" \
  "[.. | objects | select(has(\"key\") and has(\"value\"))
    | select((.key | tostring | test(\"$CRED_KEYS\"; \"i\")) and ((.value | tostring | $PLACEHOLDER) | not))
    | .value] | .[] | tostring"

# Auth blocks (apikey/bearer/basic/oauth2) store the secret under key value/token/password/...
scan_jq "literal credential in an auth block" \
  "[.. | objects | select(has(\"auth\")) | .auth | objects | to_entries[] | select(.key != \"type\") | .value | arrays | .[]
    | select((.key | tostring | test(\"^(value|token|password|username|accessToken|refreshToken|clientSecret|clientToken|secretKey|accessKey|authKey)\$\")) and ((.value | tostring | $PLACEHOLDER) | not))
    | .value] | .[] | tostring"

scan "recorded session GUID (use 00000000-0000-0000-0000-000000000000)" \
  '(?<=[>:])(?!0{8}-0{4}-0{4}-0{4}-0{12})[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

scan "recorded session cookies" \
  'JSESSIONID=(?!0+(\.\w+)?[;\s"\\])[^;\s"\\]+|OFBiz\.Visitor=(?!10000(?=[;\s"\\]|$))[^;\s"\\]+'

# --- customers & people ---------------------------------------------------------------
scan "customer-identifying names / hosts" \
  '(princess ?auto|\bPAL\b|spencers?(online)?\b|scene7\.com|arc ?thrift|citi ?trends|harmons|world ?wide ?golf|lowes ?foods|alex ?lee|bass ?pro|cabela|trader ?joe|half ?price ?books|familiprix|goodwill|\bhertz\b|\bthrifty\b|\brona\b|\bwnpa?\b|western ?national|eastside ?sports|\bmuji\b|crazy ?shirts)'

# Names in XML tags (raw or HTML-escaped in descriptions), JSON keys and query params.
# Allowed: Test / Customer / Test Customer / Associate, Sample, Nobody / Unknown (a "not found" example),
# empty, or a placeholder.
NAME_OK='(Test|Customer|Test Customer|Associate, Sample|Nobody|Unknown|String|'"$PH"'|)'
NAME_TAGS='(first_?name|last_?name|middle_?name|customer_?name|to_name|from_name|contact_name|employee_name|sales_associate|original_sales_associate)'
scan "person name in a name field (use Test / Customer / Associate, Sample)" \
  '<'"$NAME_TAGS"'>(?!'"$NAME_OK"'<)[^<]+|&lt;'"$NAME_TAGS"'&gt;(?!'"$NAME_OK"'&lt;)[^&]+|<associate_id>(?!(\d*|Associate, Sample|'"$PH"')<)[^<]+|\\?"(first_?name|last_?name)\\?"\s*:\s*\\?"(?!'"$NAME_OK"'\\?")[^"\\]+|[?&](first|last)_?name=(?!(Test|Customer)\b|'"$PH"')[^&"\\\s]+'

scan_jq "person name in a first_name/last_name parameter" \
  "[.. | objects | select(has(\"key\") and has(\"value\"))
    | select((.key | tostring | test(\"^(first|last)_?name\$\"; \"i\")) and ((.value | tostring | (test(\"^(Test|Customer)\$\") or $PLACEHOLDER)) | not))
    | .value] | .[] | tostring"

# Emails: only placeholder domains plus the documented validation fixtures (case-insensitive)
scan "email outside placeholder domains" \
  '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}' \
  '@example\.(com|org|net)$|^(support@transactiontree\.com|email@email\.com|example@donotuse\.com|example@agoodmail\.com|123@gmail\.com|customer@gmail\.com|customer@gamil\.com|do_not_email@icloud\.com)$'

# NANP phone numbers outside the reserved fictional 555-0100..0199 range
scan "phone number outside 555-01xx" \
  '(?<![0-9a-z_-])(?:\+?1[-. ]?)?\(?[2-9]\d{2}\)?[-. ]?[2-9]\d{2}[-. ]\d{4}(?![0-9a-z_-])|(?<![0-9a-z_-])\+?1?[2-9]\d{2}[2-9]\d{6}(?![0-9a-z_-])' \
  '555[-. )]*01[0-9]{2}$'

if [[ $hits -gt 0 ]]; then
  echo
  echo "internal-leak-check: $hits class(es) of finding — fix before publishing."
  exit 1
fi

echo "internal-leak-check: clean — $TARGET passed all scans."
exit 0
