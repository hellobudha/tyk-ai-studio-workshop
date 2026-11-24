#!/usr/bin/env bash
# Act 2. Tuesday. Self-service, with the right doors open for the right teams.
# Priya publishes providers in catalogs and gives each team its catalogs.
# Dana then helps herself in the AI Portal, and Priya approves with one click.
set -euo pipefail
. "$(dirname "$0")/../lib.sh"
need curl jq
openai="$(must_get llm.openai.id)"; anthropic="$(must_get llm.anthropic.id)"; harbour="$(must_get llm.harbour.id)"
dana="$(must_get user.dana.id)"; tom="$(must_get user.tom.id)"; sofia="$(must_get user.sofia.id)"

# catalogue_set NAME LLM_ID... -> id; the catalogue ends up containing exactly these providers.
catalogue_set() {
  local name="$1" id have; shift
  id="$(id_by_name /api/v1/catalogues "$name")"
  [ -n "$id" ] || id="$(api POST /api/v1/catalogues "$(jsonapi catalogues "$(jq -cn --arg n "$name" '{name:$n}')")" | jq -r .data.id)"
  have="$(api GET "/api/v1/catalogues/$id/llms" | jq -r '.data[]?.id')"
  for l in $have; do case " $* " in *" $l "*) ;; *) api DELETE "/api/v1/catalogues/$id/llms/$l" >/dev/null;; esac; done
  for l in "$@"; do
    case " $(echo $have) " in *" $l "*) ;; *) api POST "/api/v1/catalogues/$id/llms" "$(jq -cn --arg i "$l" '{data:{type:"llms",id:$i}}')" >/dev/null;; esac
  done
  printf '%s' "$id"
}

step "Act 2: nothing is available by default"
catalogue_set "Default" >/dev/null
ok "Default catalog emptied: a new joiner sees no models until a team gives them some"

step "Act 2: two LLM catalogs"
general="$(catalogue_set "General Purpose" "$openai" "$anthropic")"; ok "General Purpose  = OpenAI, Anthropic"
eures="$(catalogue_set "EU Resident" "$harbour")";                   ok "EU Resident      = Harbour EU"
put catalogue.general.id "$general"; put catalogue.eu.id "$eures"

step "Act 2: two teams"
uk="$(ensure groups /api/v1/groups "Claims UK" "$(jq -cn --argjson a "$dana" --argjson b "$tom" --argjson c "$general" \
  '{name:"Claims UK",members:[$a,$b],catalogues:[$c],data_catalogues:[],tool_catalogues:[]}')")"
ok "Claims UK  (Dana, Tom)   sees General Purpose"
eu="$(ensure groups /api/v1/groups "Claims EU" "$(jq -cn --argjson a "$sofia" --argjson c "$general" --argjson d "$eures" \
  '{name:"Claims EU",members:[$a],catalogues:[$c,$d],data_catalogues:[],tool_catalogues:[]}')")"
ok "Claims EU  (Sofia)       sees General Purpose and EU Resident"
put team.uk.id "$uk"; put team.eu.id "$eu"

if [ "${1:-}" = "--setup-only" ]; then say ""; say "Teams and catalogs are ready. Dana has not asked for anything yet."; exit 0; fi

step "Act 2: Dana helps herself in the AI Portal"
names="$(body_of "$(as dana GET /common/accessible-llms)" | jq -r '[.[]?.attributes.name // .[]?.name] | join(", ")')"
ok "Dana can see: ${names:-nothing}"

req() { jq -cn --arg n "$1" --arg d "$2" --argjson l "$3" '{name:$n,description:$d,llm_ids:$l,data_source_ids:[],tool_ids:[]}'; }
out="$(as dana POST /common/apps "$(req "Claims Copilot (EU model)" "Trying to reach a model my team was not given." "[$harbour]")")"
[ "$(code_of "$out")" = 403 ] && ok "Dana asks for Harbour EU -> 403 refused (not in her team's catalogs)" \
  || warn "expected 403 for Harbour EU, got $(code_of "$out")"

app="$(id_by_name /api/v1/apps "Claims Copilot")"
if [ -z "$app" ]; then
  out="$(as dana POST /common/apps "$(req "Claims Copilot" "Drafts claim summaries and customer letters for UK claims handlers." "[$openai,$anthropic]")")"
  [ "$(code_of "$out")" -lt 300 ] || die "Dana could not request the app: $(body_of "$out")"
  app="$(id_by_name /api/v1/apps "Claims Copilot")"
  ok "Dana requests 'Claims Copilot' with OpenAI and Anthropic (id $app): waiting for approval"
else
  ok "'Claims Copilot' already requested (id $app)"
fi
put app.claims-copilot.id "$app"
cid="$(api GET "/api/v1/apps/$app" | jq -r .data.attributes.credential_id)"
if [ "$(api GET "/api/v1/credentials/$cid" | jq -r .data.attributes.active)" != true ]; then
  key="$(api GET "/api/v1/credentials/$cid" | jq -r .data.attributes.secret)"
  code="$(code_of "$(chat "$STUDIO_GW_URL" "$key" openai/gpt-5.5-mini "Hello")")"
  ok "before approval, her key does not work yet -> HTTP $code"
fi

step "Act 2: Priya approves"
api POST "/api/v1/apps/$app/activate-credential" >/dev/null
key="$(api GET "/api/v1/credentials/$cid" | jq -r .data.attributes.secret)"
put app.claims-copilot.key "$key"
ok "credential approved"

out="$(chat "$STUDIO_GW_URL" "$key" openai/gpt-5.5-mini "Draft a short email telling a customer we received their claim.")"
[ "$(code_of "$out")" = 200 ] || die "Claims Copilot call failed: $out"
ok "Dana's app works -> HTTP 200"
out="$(chat "$STUDIO_GW_URL" "$key" harbour-eu/harbour-large "Hello")"
ok "the same key against Harbour EU -> HTTP $(code_of "$out") (the app was never granted it)"
