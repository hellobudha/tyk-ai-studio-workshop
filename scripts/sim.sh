#!/usr/bin/env bash
# Look at, and control, the simulated LLM providers.
#   ./workshop sim seen [provider] [n]   what the provider actually received (last n, default 1)
#   ./workshop sim outage <provider> on|off
#   ./workshop sim health
#   ./workshop sim reset
set -euo pipefail
. "$(dirname "$0")/lib.sh"
need curl jq
case "${1:-seen}" in
  seen)
    p="${2:-}"; n="${3:-1}"; q="last=$n"; [ -n "$p" ] && q="$q&provider=$p"
    curl -sf "$SIM_URL/_sim/requests?$q" | jq '.[] | {at, provider, vendor_key_seen, model, system, messages, tools}'
    ;;
  outage)
    p="${2:?provider: openai | anthropic | harbour}"; on="${3:?on or off}"
    [ "$on" = on ] && b=true || b=false
    curl -sf -X POST "$SIM_URL/_sim/outage" -H 'Content-Type: application/json' -d "{\"provider\":\"$p\",\"on\":$b}" | jq -c .
    ;;
  health) curl -sf "$SIM_URL/_sim/health" | jq . ;;
  reset)  curl -sf -X POST "$SIM_URL/_sim/reset" | jq -c . ;;
  *) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
