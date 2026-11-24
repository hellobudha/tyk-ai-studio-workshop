#!/usr/bin/env bash
# Shared helpers for the workshop scripts. Source it; do not run it.
#   . "$(dirname "$0")/lib.sh"

WS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
STATE_DIR="$WS_ROOT/.state"
mkdir -p "$STATE_DIR"

if [ -f "$WS_ROOT/.env" ]; then
  set -a; . "$WS_ROOT/.env"; set +a
fi

STUDIO_URL="http://localhost:${STUDIO_PORT:-8700}"
STUDIO_GW_URL="http://localhost:${STUDIO_GATEWAY_PORT:-8701}"
LONDON_URL="http://localhost:${EDGE_LONDON_PORT:-8711}"
FRANKFURT_URL="http://localhost:${EDGE_FRANKFURT_PORT:-8712}"
SIM_URL="http://localhost:${LLM_SIM_PORT:-8720}"
MERIDIAN_URL="http://localhost:${MERIDIAN_API_PORT:-8721}"

ADMIN_EMAIL="priya.nair@meridian-mutual.example"
ADMIN_NAME="Priya Nair"

c_bold=$'\033[1m'; c_dim=$'\033[2m'; c_green=$'\033[32m'; c_red=$'\033[31m'; c_yellow=$'\033[33m'; c_cyan=$'\033[36m'; c_off=$'\033[0m'
[ -t 1 ] || { c_bold=; c_dim=; c_green=; c_red=; c_yellow=; c_cyan=; c_off=; }

say()  { printf '%s\n' "$*"; }
step() { printf '\n%s== %s%s\n' "$c_bold" "$*" "$c_off"; }
ok()   { printf '%s  ok%s  %s\n' "$c_green" "$c_off" "$*"; }
warn() { printf '%s  !!%s  %s\n' "$c_yellow" "$c_off" "$*"; }
die()  { printf '%s  xx%s  %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }

need() { for b in "$@"; do command -v "$b" >/dev/null 2>&1 || die "'$b' is required but not installed"; done; }

# --- state: small key/value files under .state/ (gitignored) -----------------
put() { printf '%s' "$2" > "$STATE_DIR/$1"; }
get() { if [ -f "$STATE_DIR/$1" ]; then cat "$STATE_DIR/$1"; fi; }
must_get() { local v; v="$(get "$1")"; [ -n "$v" ] || die "missing state '$1': run ./workshop seed first"; printf '%s' "$v"; }

# --- management API ----------------------------------------------------------
# api METHOD PATH [JSON]  -> prints the response body; fails on HTTP >= 400.
api() {
  local method="$1" path="$2" body="${3:-}" key out code
  key="$(must_get admin.key)"
  out="$(mktemp)"
  if [ -n "$body" ]; then
    code="$(curl -sS -o "$out" -w '%{http_code}' -X "$method" "$STUDIO_URL$path" \
      -H "Authorization: Bearer $key" -H 'Content-Type: application/json' -d "$body")"
  else
    code="$(curl -sS -o "$out" -w '%{http_code}' -X "$method" "$STUDIO_URL$path" \
      -H "Authorization: Bearer $key")"
  fi
  if [ "$code" -ge 400 ]; then
    printf '%s %s -> HTTP %s: %s\n' "$method" "$path" "$code" "$(head -c 600 "$out")" >&2
    rm -f "$out"; return 1
  fi
  cat "$out"; rm -f "$out"
}

# jsonapi TYPE ATTRIBUTES_JSON -> the JSON:API envelope AI Studio expects.
jsonapi() { jq -cn --arg t "$1" --argjson a "$2" '{data:{type:$t,attributes:$a}}'; }

# id_by_name LIST_PATH NAME -> id of the object whose attributes.name matches (empty if none).
id_by_name() {
  local sep='?'; case "$1" in *\?*) sep='&';; esac
  api GET "$1${sep}all=true&page_size=200" | jq -r --arg n "$2" '[.data[]? | select(.attributes.name==$n) | .id][0] // empty'
}

# ensure TYPE LIST_PATH NAME ATTRIBUTES_JSON -> id (creates, or updates in place).
ensure() {
  local type="$1" path="$2" name="$3" attrs="$4" id
  id="$(id_by_name "$path" "$name")"
  if [ -n "$id" ]; then
    api PATCH "$path/$id" "$(jq -cn --arg t "$type" --arg i "$id" --argjson a "$attrs" '{data:{type:$t,id:$i,attributes:$a}}')" >/dev/null || return 1
  else
    id="$(api POST "$path" "$(jsonapi "$type" "$attrs")" | jq -r '.data.id')" || return 1
  fi
  printf '%s' "$id"
}

b64() { base64 < "$1" | tr -d '\n'; }

wait_http() { # wait_http URL [seconds]
  local url="$1" t="${2:-90}" i=0
  until curl -sf -o /dev/null "$url"; do
    i=$((i+1)); [ "$i" -ge "$t" ] && return 1; sleep 1
  done
}

# --- story fixtures ----------------------------------------------------------
# The prompt a claims handler pasted into a public chatbot on Monday morning.
# Every identifier in it is fake but correctly formed, so detectors treat it as real.
MONDAY_PROMPT='Summarise this claim for the file. Customer Amara Osei, date of birth 14/03/1987, National Insurance number AB 12 34 56 C, email amara.osei@example.com. Refund to IBAN GB29 NWBK 6016 1331 9268 19. Escape of water in the kitchen, policy POL-20418.'

month_start() { date -u +%Y-%m-01T00:00:00Z; }
today() { date -u +%Y-%m-%d; }

# chat GATEWAY_URL APP_SECRET MODEL PROMPT -> raw response body, HTTP code on the last line.
chat() {
  curl -sS -w '\n%{http_code}' "$1/v1/chat/completions" \
    -H "Authorization: Bearer $2" -H 'Content-Type: application/json' \
    -d "$(jq -cn --arg m "$3" --arg p "$4" '{model:$m,messages:[{role:"user",content:$p}]}')"
}

# ensure_secret NAME VALUE -> id
ensure_secret() {
  local id body
  body="$(jsonapi secrets "$(jq -cn --arg n "$1" --arg v "$2" '{var_name:$n,value:$v}')")"
  id="$(api GET "/api/v1/secrets?all=true&page_size=200" | jq -r --arg n "$1" '[.data[]|select(.attributes.var_name==$n)|.id][0] // empty')"
  if [ -n "$id" ]; then api PATCH "/api/v1/secrets/$id" "$body" >/dev/null; else id="$(api POST /api/v1/secrets "$body" | jq -r .data.id)"; fi
  printf '%s' "$id"
}

# ensure_price MODEL VENDOR INPUT_PER_MILLION OUTPUT_PER_MILLION
ensure_price() {
  local id attrs
  attrs="$(jq -cn --arg m "$1" --arg v "$2" --argjson i "$3" --argjson o "$4" '{model_name:$m,vendor:$v,cpit:($i/1000000),cpt:($o/1000000),currency:"USD"}')"
  id="$(api GET "/api/v1/model-prices?all=true&page_size=500" | jq -r --arg m "$1" --arg v "$2" '[.data[]|select(.attributes.model_name==$m and .attributes.vendor==$v)|.id][0] // empty')"
  if [ -n "$id" ]; then
    api PATCH "/api/v1/model-prices/$id" "$(jq -cn --arg i "$id" --argjson a "$attrs" '{data:{type:"model-prices",id:$i,attributes:$a}}')" >/dev/null
  else
    api POST /api/v1/model-prices "$(jsonapi model-prices "$attrs")" >/dev/null
  fi
}

# ensure_app NAME DESCRIPTION OWNER_USER_ID EXTRA_ATTRS_JSON -> app id; saves the secret to .state/app.<slug>.key
ensure_app() {
  local name="$1" attrs id cid slug
  attrs="$(jq -cn --arg n "$1" --arg d "$2" --argjson u "$3" --argjson x "$4" '{name:$n,description:$d,user_id:$u,is_active:true} + $x')"
  id="$(ensure apps /api/v1/apps "$name" "$attrs")" || return 1
  api POST "/api/v1/apps/$id/activate-credential" >/dev/null || return 1
  cid="$(api GET "/api/v1/apps/$id" | jq -r .data.attributes.credential_id)"
  slug="$(printf '%s' "$name" | tr 'A-Z ' 'a-z-')"
  put "app.$slug.id" "$id"
  put "app.$slug.key" "$(api GET "/api/v1/credentials/$cid" | jq -r .data.attributes.secret)"
  printf '%s' "$id"
}

# user_key NAME -> an API key for that person (rolled once, then cached in .state)
user_key() {
  local k; k="$(get "user.$1.key")"
  if [ -z "$k" ] || ! curl -sf -o /dev/null -H "Authorization: Bearer $k" "$STUDIO_URL/common/me"; then
    k="$(api POST "/api/v1/users/$(must_get "user.$1.id")/roll-api-key" | jq -r '.data.api_key // .api_key // .data.attributes.api_key // empty')"
    [ -n "$k" ] || die "could not get an API key for $1"
    put "user.$1.key" "$k"
  fi
  printf '%s' "$k"
}

# as NAME METHOD PATH [JSON] -> "<body>\n<http code>" calling the API as that person.
as() {
  local k; k="$(user_key "$1")" || return 1
  if [ -n "${4:-}" ]; then
    curl -sS -w '\n%{http_code}' -X "$2" "$STUDIO_URL$3" -H "Authorization: Bearer $k" -H 'Content-Type: application/json' -d "$4"
  else
    curl -sS -w '\n%{http_code}' -X "$2" "$STUDIO_URL$3" -H "Authorization: Bearer $k"
  fi
}
code_of() { printf '%s' "${1##*$'\n'}"; }
body_of() { printf '%s' "${1%$'\n'*}"; }

# filter_id NAME -> id (the filters list is a bare array, unlike the other resources)
filter_id() { api GET /api/v1/filters | jq -r --arg n "$1" '[.[]|select(.attributes.name==$n)|.id][0] // empty'; }

# ensure_script_filter NAME DESCRIPTION FILE [response_filter] -> id
ensure_script_filter() {
  local id attrs
  attrs="$(jq -cn --arg n "$1" --arg d "$2" --arg s "$(b64 "$3")" --argjson r "${4:-false}" '{name:$n,description:$d,kind:"script",response_filter:$r,script:$s}')"
  id="$(filter_id "$1")"
  if [ -n "$id" ]; then
    api PATCH "/api/v1/filters/$id" "$(jq -cn --arg i "$id" --argjson a "$attrs" '{data:{type:"filters",id:$i,attributes:$a}}')" >/dev/null || return 1
  else
    api POST /api/v1/filters "$(jsonapi filters "$attrs")" >/dev/null || return 1
    id="$(filter_id "$1")"
  fi
  printf '%s' "$id"
}

# llm_set LLM_ID ATTRS_JSON: partial update of a provider.
llm_set() { api PATCH "/api/v1/llms/$1" "$(jq -cn --arg i "$1" --argjson a "$2" '{data:{type:"llms",id:$i,attributes:$a}}')" >/dev/null; }

# sim_last [provider] -> the last prompt that provider received
sim_last() { curl -sS "$SIM_URL/_sim/requests?last=1${1:+&provider=$1}" | jq -r '.[0].messages[-1].content // "(nothing received)"'; }

# push_config: send the current configuration to every edge gateway and wait until all report in sync.
push_config() {
  local i pending
  api POST /api/v1/edges/reload-all '{}' >/dev/null || return 1
  for i in $(seq 1 30); do
    sleep 2
    pending="$(api GET /api/v1/sync/status | jq '[.data[] | select(.total_edges>0) | (.total_edges - .synced_count)] | add // 0')"
    [ "$pending" = 0 ] && return 0
  done
  return 1
}
sync_table() { api GET /api/v1/edges | jq -r '.data[].attributes | "  \(.edge_id)\tnamespace \(.namespace)\t\(.status)\t\(.sync_status)\tconfig \(.loaded_checksum[0:10])"'; }
