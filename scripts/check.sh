#!/usr/bin/env bash
# ./workshop check <n>: is Act n in place? Read-only. Exits non-zero if something is missing.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
need curl jq
n="${1:-}"; fails=0
pass() { ok "$1"; }
fail() { printf '%s  --%s  %s\n' "$c_red" "$c_off" "$1"; fails=$((fails+1)); }
has() { [ -n "$1" ] && pass "$2" || fail "$2"; }
gw_code() { code_of "$(chat "$1" "$2" "$3" "Hello")"; }

llm() { api GET "/api/v1/llms?all=true&page_size=100" | jq -c --arg n "$1" '.data[]|select(.attributes.name==$n)|.attributes'; }
app_key() { # app_key NAME -> secret (empty if the app or an active credential is missing)
  local id cid; id="$(id_by_name /api/v1/apps "$1")"; [ -n "$id" ] || return 0
  cid="$(api GET "/api/v1/apps/$id" | jq -r .data.attributes.credential_id)"
  api GET "/api/v1/credentials/$cid" | jq -r 'select(.data.attributes.active==true)|.data.attributes.secret'
}

case "$n" in
1)
  step "Check 1: one front door"
  for name in "OpenAI" "Anthropic" "Harbour EU"; do
    a="$(llm "$name")"
    [ -n "$a" ] && printf '%s' "$a" | jq -e '.api_endpoint|test("llm-sim")' >/dev/null && pass "provider '$name' points at the simulator" || fail "provider '$name' is missing or does not point at the simulator"
    [ -n "$a" ] && [ "$(printf '%s' "$a" | jq -r .credential_status)" = secret ] && pass "provider '$name' takes its key from a secret" || fail "provider '$name' does not use a secret for its key"
  done
  [ "$(api GET "/api/v1/model-prices?all=true&page_size=500" | jq '[.data[]|select(.attributes.model_name|test("gpt-5.5|claude-(sonnet|haiku)-5-5|harbour-large"))]|length')" -ge 5 ] && pass "five model prices" || fail "model prices are missing"
  k="$(app_key "Platform Smoke Test")"; has "$k" "app 'Platform Smoke Test' has an active credential"
  [ -n "$k" ] && { [ "$(gw_code "$STUDIO_GW_URL" "$k" openai/gpt-5.5-mini)" = 200 ] && pass "a call through the gateway returns 200" || fail "a call through the gateway does not return 200"; }
  ;;
2)
  step "Check 2: teams, catalogs, self-service"
  g="$(api GET "/api/v1/groups?all=true&page_size=100")"
  for t in "Claims UK" "Claims EU"; do printf '%s' "$g" | jq -e --arg n "$t" '.data[]|select(.attributes.name==$n)' >/dev/null && pass "team '$t'" || fail "team '$t' is missing"; done
  printf '%s' "$g" | jq -e '.data[]|select(.attributes.name=="Claims UK")|.attributes.catalogue_names|index("General Purpose")' >/dev/null && pass "Claims UK has the General Purpose catalog" || fail "Claims UK does not have the General Purpose catalog"
  printf '%s' "$g" | jq -e '.data[]|select(.attributes.name=="Claims EU")|.attributes.catalogue_names|index("EU Resident")' >/dev/null && pass "Claims EU has the EU Resident catalog" || fail "Claims EU does not have the EU Resident catalog"
  k="$(app_key "Claims Copilot")"; has "$k" "app 'Claims Copilot' is approved"
  [ -n "$k" ] && { [ "$(gw_code "$STUDIO_GW_URL" "$k" openai/gpt-5.5-mini)" = 200 ] && pass "Claims Copilot can call OpenAI" || fail "Claims Copilot cannot call OpenAI"
                   [ "$(gw_code "$STUDIO_GW_URL" "$k" harbour-eu/harbour-large)" != 200 ] && pass "Claims Copilot cannot call Harbour EU" || fail "Claims Copilot can call Harbour EU (it should not)"; }
  ;;
3)
  step "Check 3: guardrails"
  for name in "OpenAI" "Anthropic"; do
    c="$(llm "$name" | jq '.filters|length')"; [ "${c:-0}" -ge 4 ] && pass "provider '$name' has $c filters attached" || fail "provider '$name' has ${c:-0} filters attached (expected 4)"
  done
  k="$(app_key "Claims Copilot")"
  if [ -n "$k" ]; then
    chat "$STUDIO_GW_URL" "$k" openai/gpt-5.5-mini "$MONDAY_PROMPT" >/dev/null
    sim_last openai | grep -q 'REDACTED:UK_NINO' && pass "personal data is redacted before OpenAI sees it" || fail "OpenAI still receives the National Insurance number"
    [ "$(code_of "$(chat "$STUDIO_GW_URL" "$k" openai/gpt-5.5-mini "Summarise SIU-48213")")" = 400 ] && pass "an SIU case reference is blocked" || fail "an SIU case reference is not blocked"
  else fail "app 'Claims Copilot' is missing (Act 2)"; fi
  ;;
4)
  step "Check 4: budgets"
  [ "$(api GET /api/v1/team-budgets/settings | jq -r .enabled)" = true ] && pass "team budgets are switched on" || fail "team budgets are switched off"
  uk="$(id_by_name /api/v1/groups "Claims UK")"
  [ -n "$uk" ] && [ "$(api GET "/api/v1/groups/$uk/budget" | jq -r '.monthly_budget // 0')" != 0 ] && pass "Claims UK has a monthly budget" || fail "Claims UK has no monthly budget"
  k="$(app_key "Backlog Summariser")"; has "$k" "app 'Backlog Summariser' exists"
  [ -n "$k" ] && { [ "$(gw_code "$STUDIO_GW_URL" "$k" openai/gpt-5.5)" = 403 ] && pass "Backlog Summariser is stopped by its budget (403)" || fail "Backlog Summariser has not hit its budget yet (run the loop in Act 4)"; }
  ;;
5)
  step "Check 5: tools, knowledge, chat"
  t="$(api GET "/api/v1/tools?all=true&page_size=100" | jq -c '.data[]|select(.attributes.name=="Policy and Claims")|.attributes')"
  has "$t" "tool 'Policy and Claims'"
  [ -n "$t" ] && { [ "$(printf '%s' "$t" | jq '.filters|length')" -ge 1 ] && pass "the tool has a response filter" || fail "the tool has no filter"; }
  has "$(id_by_name /api/v1/datasources "Claims Handbook")" "data source 'Claims Handbook'"
  has "$(id_by_name /api/v1/chats "Claims Assistant")" "chat 'Claims Assistant'"
  k="$(app_key "Claims Triage Agent")"; has "$k" "app 'Claims Triage Agent' is approved"
  if [ -n "$k" ]; then
    r="$(curl -sS "$STUDIO_GW_URL/tools/policy-and-claims" -H "Authorization: Bearer $k" -H 'Content-Type: application/json' -d '{"operation_id":"getPolicy","parameters":{"policy_id":["POL-20418"]}}')"
    printf '%s' "$r" | jq -e '.status=="In force"' >/dev/null && pass "the tool answers through the gateway" || fail "the tool does not answer through the gateway: $r"
    printf '%s' "$r" | grep -q 'GB29' && fail "the tool still returns the bank account" || pass "the bank account is withheld"
  fi
  ;;
6)
  step "Check 6: regions and resilience"
  e="$(api GET /api/v1/edges)"
  for id in edge-london edge-frankfurt; do printf '%s' "$e" | jq -e --arg i "$id" '.data[]|select(.attributes.edge_id==$i and .attributes.status=="connected" and .attributes.sync_status=="in_sync")' >/dev/null && pass "$id is connected and in sync" || fail "$id is not connected or not in sync (push configuration)"; done
  [ "$(llm "Harbour EU" | jq -r .namespace)" = eu ] && pass "Harbour EU is in namespace 'eu'" || fail "Harbour EU is not in namespace 'eu'"
  k="$(app_key "Claims Triage Agent")"
  [ -n "$k" ] && { [ "$(gw_code "$FRANKFURT_URL" "$k" harbour-eu/harbour-large)" = 200 ] && pass "Frankfurt serves Harbour EU" || fail "Frankfurt does not serve Harbour EU"
                   [ "$(gw_code "$LONDON_URL" "$k" harbour-eu/harbour-large)" != 200 ] && pass "London does not serve Harbour EU" || fail "London serves Harbour EU (it should not)"; }
  [ "$(llm "OpenAI" | jq '.failover.targets|length')" -ge 1 ] 2>/dev/null && pass "OpenAI has a failover target" || fail "OpenAI has no failover target"
  k="$(app_key "Claims Copilot")"
  [ -n "$k" ] && { [ "$(gw_code "$LONDON_URL" "$k" meridian/fast)" = 200 ] && pass "meridian/fast answers at the London edge" || fail "meridian/fast does not answer at the London edge"; }
  ;;
7)
  step "Check 7: prove it"
  for pair in marcus:auditor elena:viewer; do
    who="${pair%%:*}"; role="${pair#*:}"
    body_of "$(as "$who" GET /common/me)" | jq -e --arg r "$role" '.attributes.roles[]?|select(.slug==$r)' >/dev/null && pass "$who has the $role role" || fail "$who does not have the $role role"
  done
  [ "$(code_of "$(as marcus GET /api/v1/audit/summary)")" = 200 ] && pass "Marcus can read the audit trail" || fail "Marcus cannot read the audit trail"
  [ "$(code_of "$(as marcus PATCH "/api/v1/llms/999999" '{"data":{"type":"llms","id":"999999","attributes":{}}}')")" = 403 ] && pass "Marcus cannot change a provider" || fail "Marcus can change a provider"
  ;;
*) echo "usage: ./workshop check <1-7>"; exit 1;;
esac
echo
[ "$fails" -eq 0 ] && say "${c_green}Act $n is in place.${c_off}" || { say "${c_red}$fails thing(s) missing for Act $n.${c_off} ./workshop act $n does the act for you."; exit 1; }
