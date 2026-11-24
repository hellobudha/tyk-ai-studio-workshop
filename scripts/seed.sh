#!/usr/bin/env bash
# Monday 08:00 at Meridian Mutual: a fresh AI Studio, the people in the story, nothing governed yet.
# Safe to run again.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
need curl jq

step "Waiting for AI Studio"
wait_http "$STUDIO_URL/health" 120 || die "AI Studio did not answer on $STUDIO_URL (./workshop logs studio)"
ok "AI Studio is up at $STUDIO_URL"

step "First administrator"
"$WS_ROOT/scripts/bootstrap-admin.sh"
put user.priya.id "$(api GET /common/me | jq -r .id)"

step "The people in the story"
# name | email local part | portal | chat
while IFS='|' read -r name local portal chat; do
  email="$local@meridian-mutual.example"
  id="$(api GET "/api/v1/users?all=true&page_size=200" | jq -r --arg e "$email" '[.data[]|select(.attributes.email==$e)|.id][0] // empty')"
  if [ -z "$id" ]; then
    id="$(api POST /api/v1/users "$(jsonapi users "$(jq -cn --arg e "$email" --arg n "$name" --arg p "$WS_USER_PASSWORD" \
      --argjson portal "$portal" --argjson chat "$chat" \
      '{email:$e,name:$n,password:$p,is_admin:false,show_portal:$portal,show_chat:$chat,email_verified:true}')")" | jq -r .data.id)"
    ok "created $name <$email>"
  else
    ok "$name already exists"
  fi
  put "user.${local%%.*}.id" "$id"
done <<'CAST'
Dana Okafor|dana.okafor|true|true
Tom Reyes|tom.reyes|false|true
Sofia Keller|sofia.keller|true|true
Marcus Bell|marcus.bell|false|false
Elena Rossi|elena.rossi|false|false
CAST

step "Nothing leaves this machine"
# A fresh AI Studio ships with OpenAI and Anthropic entries that point at the real vendors.
# Until Act 1 gives them the simulator's address, park them on an address that cannot resolve,
# and hand the edges that configuration, so no prompt can reach the internet by accident.
parked=0
for row in $(api GET "/api/v1/llms?all=true&page_size=100" | jq -r '.data[] | select(.attributes.api_endpoint | test("api\\.(openai|anthropic)\\.com")) | .id'); do
  llm_set "$row" '{"api_endpoint":"http://not-configured.invalid/v1"}'; parked=$((parked+1))
done
if [ "$parked" -gt 0 ]; then
  ok "$parked default provider(s) parked on a placeholder address until Act 1"
  push_config && ok "edge gateways hold the same configuration" || warn "edges not in sync yet (they will retry)"
else
  ok "no provider points at a real vendor"
fi

step "Simulators"
curl -sf -X POST "$SIM_URL/_sim/reset" >/dev/null && ok "LLM simulator reset ($SIM_URL)"
curl -sf "$MERIDIAN_URL/health" >/dev/null && ok "Meridian Policy & Claims API is up ($MERIDIAN_URL)"

say ""
say "Ready. Open ${c_bold}$STUDIO_URL${c_off} and sign in as Priya:"
say "  email     $ADMIN_EMAIL"
say "  password  (run ./workshop who)"
