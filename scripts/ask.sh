#!/usr/bin/env bash
# Send one chat request through a gateway as one of the workshop's Apps.
#
#   ./workshop ask <app> <model> "<prompt>" [--at studio|london|frankfurt] [--headers] [--times N]
#   ./workshop ask claims-copilot openai/gpt-5.5-mini "Which model are you?"
#   ./workshop ask claims-copilot openai/gpt-5.5-mini @stack/prompts/monday.txt
#
# <app> is the App's name in lower case with dashes (claims-copilot, platform-smoke-test, ...).
# It prints the request it makes (never the App's secret), the HTTP status, and the answer.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
need curl jq
[ $# -ge 3 ] || { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
app="$1"; model="$2"; prompt="$3"; shift 3
at=studio; headers=0; times=1
while [ $# -gt 0 ]; do case "$1" in
  --at) at="$2"; shift 2;; --headers) headers=1; shift;; --times) times="$2"; shift 2;;
  *) die "unknown option $1";; esac; done
case "$at" in studio) url="$STUDIO_GW_URL";; london) url="$LONDON_URL";; frankfurt) url="$FRANKFURT_URL";; *) die "--at studio|london|frankfurt";; esac
key="$(get "app.$app.key")"
if [ -z "$key" ]; then
  # An app you built by hand in the console: look it up by name and use its active credential.
  id="$(api GET "/api/v1/apps?all=true&page_size=200" | jq -r --arg s "$app" '[.data[] | select((.attributes.name | ascii_downcase | gsub(" "; "-")) == $s) | .id][0] // empty')"
  [ -n "$id" ] || die "no app called '$app' (use its name in lower case with dashes, for example claims-copilot)"
  cid="$(api GET "/api/v1/apps/$id" | jq -r .data.attributes.credential_id)"
  key="$(api GET "/api/v1/credentials/$cid" | jq -r 'select(.data.attributes.active==true) | .data.attributes.secret')"
  [ -n "$key" ] || die "app '$app' has no approved credential yet (AI Portal > Apps > Approve this App)"
fi
case "$prompt" in @*) prompt="$(cat "$WS_ROOT/${prompt#@}")";; esac
body="$(jq -cn --arg m "$model" --arg p "$prompt" '{model:$m,messages:[{role:"user",content:$p}]}')"

say "POST $url/v1/chat/completions   app: $app   model: $model"
if [ "$times" -gt 1 ]; then
  for _ in $(seq 1 "$times"); do
    curl -sS -D - -o /dev/null "$url/v1/chat/completions" -H "Authorization: Bearer $key" -H 'Content-Type: application/json' -d "$body" \
      | awk 'tolower($1)=="x-tyk-served-model:"{print $2}' | tr -d '\r'
  done | sort | uniq -c | awk '{printf "  served by %-20s %s of '"$times"'\n", $2, $1}'
  exit 0
fi
hdr="$(mktemp)"; out="$(mktemp)"; trap 'rm -f "$hdr" "$out"' EXIT
code="$(curl -sS -D "$hdr" -o "$out" -w '%{http_code}' "$url/v1/chat/completions" -H "Authorization: Bearer $key" -H 'Content-Type: application/json' -d "$body")"
say "HTTP $code"
[ "$headers" = 1 ] && grep -iE '^x-tyk-' "$hdr" | tr -d '\r' | sed 's/^/  /'
if [ "$code" = 200 ]; then
  jq -r '.choices[0].message.content' "$out"
else
  jq -r '.error.message // .message // .' "$out" 2>/dev/null | sed 's/^\[ERROR\] msg: policy_violation err: //' || cat "$out"
fi
