#!/usr/bin/env bash
# Act 4. Wednesday night into Thursday. Money: budgets that actually stop the spend.
# Elena and Priya give the Claims UK team a monthly budget, cap a new batch job,
# and the job's bug meets the cap at 02:00 instead of the invoice at month end.
set -euo pipefail
. "$(dirname "$0")/../lib.sh"
need curl jq python3
openai="$(must_get llm.openai.id)"; uk="$(must_get team.uk.id)"; dana="$(must_get user.dana.id)"

step "Act 4: a monthly budget for the Claims UK team"
api PUT /api/v1/team-budgets/settings '{"enabled":true}' >/dev/null
api PUT "/api/v1/groups/$uk/budget" "$(jq -cn --arg s "$(month_start)" \
  '{monthly_budget:50,budget_start_date:$s,default_app_allocation:5,enforcement:"hard_block"}')" >/dev/null
ok "Claims UK: \$50 a month, hard block, new apps start with \$5"

step "Act 4: a ceiling on the public provider as a whole"
llm_set "$openai" "$(jq -cn --arg s "$(month_start)" '{monthly_budget:500,budget_start_date:$s}')"
ok "OpenAI: \$500 a month across every app"

step "Act 4: Dana's new batch job gets a \$1 trial budget"
# --fresh throws the job away and starts it again (for rehearsing or recording the act).
if [ "${1:-}" = "--fresh" ]; then
  old="$(id_by_name /api/v1/apps "Backlog Summariser")"
  [ -n "$old" ] && api DELETE "/api/v1/apps/$old" >/dev/null && ok "removed the previous Backlog Summariser"
fi
app="$(ensure_app "Backlog Summariser" "Nightly batch job that re-summarises open claim files." "$dana" \
  "$(jq -cn --argjson a "$openai" --arg s "$(month_start)" --argjson t "$uk" '{llm_ids:[$a],monthly_budget:1,budget_start_date:$s,team_id:$t}')")"
ok "app 'Backlog Summariser' (id $app), \$1 a month"

if [ "${1:-}" = "--setup-only" ] || [ "${2:-}" = "--setup-only" ]; then say ""; say "Budgets are set. The job has not run yet: ./workshop runaway"; exit 0; fi

step "Act 4: 02:00. The job has a bug: it resends the same 40-page claim file forever"
"$WS_ROOT/scripts/runaway.sh"

step "Act 4: what it cost, and who it belongs to"
d="$(today)"
api GET "/api/v1/analytics/team-costs?start_date=$d&end_date=$d" \
  | jq -r '.teams[] | "  team \(.team_name): $\(.cost*100|round/100)  \(.requests) requests  \(.tokens) tokens"'
say ""
say "The other Claims UK app is untouched: Claims Copilot still answers."
out="$(chat "$STUDIO_GW_URL" "$(must_get app.claims-copilot.key)" openai/gpt-5.5-mini "Hello")"
ok "Claims Copilot -> HTTP $(code_of "$out")"
