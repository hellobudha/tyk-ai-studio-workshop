#!/usr/bin/env bash
# Talk to the Policy and Claims tool the way an AI agent does: over MCP, as the Claims Triage Agent app.
#   ./workshop mcp                       list the tools, then look up policy POL-20418
#   ./workshop mcp getClaim CLM-77120    call one tool
set -euo pipefail
. "$(dirname "$0")/lib.sh"
need curl jq
key="$(get app.claims-triage-agent.key)"; [ -n "$key" ] || die "the Claims Triage Agent app does not exist yet (./workshop act 5)"
op="${1:-getPolicy}"; id="${2:-POL-20418}"
case "$op" in getPolicy) arg=policy_id;; getClaim) arg=claim_id;; *) die "tool must be getPolicy or getClaim";; esac
mcp="$STUDIO_GW_URL/tools/policy-and-claims/mcp"
H=(-H "Authorization: Bearer $key" -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream')
say "MCP endpoint: $mcp   app: claims-triage-agent"
hdr="$(mktemp)"; trap 'rm -f "$hdr"' EXIT
curl -sS -D "$hdr" -o /dev/null "$mcp" "${H[@]}" -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"claims-triage-agent","version":"1.0"}}}'
sess="$(awk 'tolower($1)=="mcp-session-id:"{print $2}' "$hdr" | tr -d '\r')"
S=(); [ -n "$sess" ] && S=(-H "Mcp-Session-Id: $sess")
say "tools/list ->"
curl -sS "$mcp" "${H[@]}" "${S[@]}" -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | jq -r '.result.tools[] | "  \(.name): \(.description)"'
say "tools/call $op $id ->"
curl -sS "$mcp" "${H[@]}" "${S[@]}" -d "$(jq -cn --arg o "$op" --arg a "$arg" --arg i "$id" '{jsonrpc:"2.0",id:3,method:"tools/call",params:{name:$o,arguments:{($a):$i}}}')" \
  | jq -r '.result.content[0].text // .error.message' | jq . 2>/dev/null || true
