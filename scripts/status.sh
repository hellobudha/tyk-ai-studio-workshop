#!/usr/bin/env bash
# What is running, and how far the story has got.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
need curl jq docker
step "Containers"
(cd "$WS_ROOT" && docker compose ps --format '  {{.Service}}\t{{.Status}}')
step "Where things are"
say "  Admin console, AI Portal, Chat   $STUDIO_URL"
say "  Gateway inside AI Studio         $STUDIO_GW_URL"
say "  Edge gateway, London (uk)        $LONDON_URL"
say "  Edge gateway, Frankfurt (eu)     $FRANKFURT_URL"
say "  Simulated LLM providers          $SIM_URL"
say "  Meridian Policy & Claims API     $MERIDIAN_URL"
if [ -z "$(get admin.key)" ] || ! curl -sf -o /dev/null -H "Authorization: Bearer $(get admin.key)" "$STUDIO_URL/common/me"; then
  say ""; warn "AI Studio is not reachable with the saved admin key. Run ./workshop up."; exit 0
fi
sys="$(api GET /common/system)"
step "AI Studio"
say "  $(printf '%s' "$sys" | jq -r '"version \(.version), \(.edition) edition"')"
step "The story so far"
for n in 1 2 3 4 5 6 7; do
  if "$WS_ROOT/scripts/check.sh" "$n" >/dev/null 2>&1; then printf '  %sdone%s     Act %s\n' "$c_green" "$c_off" "$n"; else printf '  %sto do%s    Act %s\n' "$c_dim" "$c_off" "$n"; fi
done
