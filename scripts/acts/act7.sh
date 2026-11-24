#!/usr/bin/env bash
# Act 7. Friday afternoon. Prove it.
# The regulator's question was "which models touch customer data, who decided, and how
# do you know?". Marcus answers it himself, read-only, from the record.
set -euo pipefail
. "$(dirname "$0")/../lib.sh"
need curl jq
marcus="$(must_get user.marcus.id)"; elena="$(must_get user.elena.id)"

bind() { # bind USER_ID ROLE_SLUG
  local rid; rid="$(api GET /api/v1/rbac/roles | jq -r --arg s "$2" '.data[]|select(.attributes.slug==$s)|.id')"
  if [ -z "$(api GET "/api/v1/rbac/bindings?subject_type=user&subject_id=$1&role_id=$rid" | jq -r '.data[0].id // empty')" ]; then
    api POST /api/v1/rbac/bindings "$(jq -cn --argjson r "$rid" --argjson u "$1" '{subject_type:"user",subject_id:$u,role_id:$r}')" >/dev/null
  fi
}

step "Act 7: least privilege for the people who check"
bind "$marcus" auditor; ok "Marcus Bell  -> Auditor (reads everything, including the audit trail and logs; changes nothing)"
bind "$elena" viewer;   ok "Elena Rossi  -> Viewer  (configuration and spend; no prompts, no logs)"

step "Act 7: Marcus tries to switch the guardrails off"
out="$(as marcus PATCH "/api/v1/llms/$(must_get llm.openai.id)" "$(jq -cn --arg i "$(must_get llm.openai.id)" '{data:{type:"llms",id:$i,attributes:{filters:[]}}}')")"
ok "HTTP $(code_of "$out"): $(body_of "$out" | jq -r '.errors[0].detail')"

step "Act 7: Elena tries to read a prompt"
d="$(today)"
out="$(as elena GET "/api/v1/analytics/proxy-logs-for-app?app_id=$(must_get app.claims-copilot.id)&start_date=$d&end_date=$d&page_size=1")"
ok "HTTP $(code_of "$out"): $(body_of "$out" | jq -r '.errors[0].detail // "allowed"')"

step "Act 7: the audit trail, read by Marcus"
out="$(as marcus GET /api/v1/audit/summary)"
[ "$(code_of "$out")" = 200 ] || die "Marcus could not read the audit trail: $out"
body_of "$out" | jq -r '"  \(.total) recorded actions by \(.distinct_users) people, \(.failed) refused or failed"'
body_of "$out" | jq -r '.by_action[0:8][] | "    \(.count)\t\(.name)"'

step "Act 7: who changed the OpenAI provider, and what exactly?"
body_of "$(as marcus GET "/api/v1/audit/resources/llm/$(must_get llm.openai.id)")" \
  | jq -r '(.data // .records // .)[0:6][] | "  \(.timestamp[11:19])  \(.user_name)  \(.action)  HTTP \(.status)  changed: \((.diff // {}) | keys | join(", ") | if .=="" then "-" else . end)"'

step "Act 7: the compliance picture for today"
body_of "$(as marcus GET "/api/v1/compliance/summary?start_date=$d&end_date=$d")" \
  | jq -r '"  \(.total_requests) requests, \(.policy_violations) blocked by policy, \(.budget_alerts) budget alerts, \(.compliance_events_critical) critical and \(.compliance_events_warning) warning events"'
