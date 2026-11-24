#!/usr/bin/env bash
# The Backlog Summariser's bug: it sends the same 40-page claim file again and again,
# with no retry limit. Run it and watch the budget stop it.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
need curl jq python3
key="$(get app.backlog-summariser.key)"; app="$(get app.backlog-summariser.id)"
[ -n "$key" ] || die "the Backlog Summariser app does not exist yet (./workshop act 4)"
file="$(python3 -c "print('Claim file note: the customer reported an escape of water in the kitchen and the loss adjuster attended on site. ' * 900)")"
body="$(jq -cn --arg p "Summarise this claim file. $file" '{model:"openai/gpt-5.5",messages:[{role:"user",content:$p}]}')"
say "Backlog Summariser: sending a 40-page claim file to openai/gpt-5.5, again and again..."
n=0; code=200; out=
printf '  '
while [ "$n" -lt 60 ]; do
  n=$((n+1))
  out="$(curl -sS -w '\n%{http_code}' "$STUDIO_GW_URL/v1/chat/completions" -H "Authorization: Bearer $key" -H 'Content-Type: application/json' -d "$body")"
  code="$(code_of "$out")"; printf '%s ' "$code"
  [ "$code" = 200 ] || break
done; echo
if [ "$code" = 403 ]; then
  say "Call $n refused: $(body_of "$out" | jq -r .error.message)"
else
  die "expected the budget to stop the job with 403, last code was $code"
fi
api GET "/api/v1/analytics/budget-usage-for-app?app_id=$app" \
  | jq -r '"Spent $\(.current_usage*100|round/100) of a $\(.monthly_budget) monthly budget."'
[ "$n" -gt 1 ] || say "(It was already over budget. ./workshop act 4 --fresh starts it again from zero.)"
