#!/usr/bin/env bash
# Act 6. Friday morning. Regions and resilience.
# Traffic moves to edge gateways in London and Frankfurt. The private model is served
# only from Frankfurt. An OpenAI outage fails over on its own. Apps ask for a
# capability ("fast", "quality") and Priya decides which vendor answers.
set -euo pipefail
. "$(dirname "$0")/../lib.sh"
need curl jq
openai="$(must_get llm.openai.id)"; anthropic="$(must_get llm.anthropic.id)"; harbour="$(must_get llm.harbour.id)"
general="$(must_get catalogue.general.id)"; dana="$(must_get user.dana.id)"
copilot="$(must_get app.claims-copilot.id)"; kc="$(must_get app.claims-copilot.key)"; ka="$(must_get app.claims-triage-agent.key)"

step "Act 6: two edge gateways are connected to the control plane"
sync_table

step "Act 6: the private model is served from Frankfurt only"
llm_set "$harbour" '{"namespace":"eu"}'
ok "Harbour EU moved to namespace 'eu'"
say "  The edges now show as out of date, and keep serving what they have:"
api GET /api/v1/sync/status | jq -r '.data[] | select(.total_edges>0) | "  namespace \(.namespace): \(.synced_count) in sync, \(.pending_count) pending"'

step "Act 6: push configuration"
push_config || die "the edges did not come back in sync (./workshop logs edge-london)"
ok "configuration pushed; both edges report the new checksum"
sync_table

step "Act 6: where can Sofia's agent reach Harbour EU?"
for pair in "London:$LONDON_URL" "Frankfurt:$FRANKFURT_URL"; do
  name="${pair%%:*}"; url="${pair#*:}"
  models="$(curl -sS "$url/v1/models" -H "Authorization: Bearer $ka" | jq -r '[.data[]?.id] | join(", ")')"
  out="$(chat "$url" "$ka" harbour-eu/harbour-large "Which model are you?")"
  say "  $name edge: models [${models:-none}]  ->  HTTP $(code_of "$out")"
done
say "  The London gateway does not have the provider at all. There is nothing to misconfigure."

step "Act 6: a failover waterfall on OpenAI"
llm_set "$openai" "$(jq -cn --argjson a "$anthropic" '{failover:{targets:[{llm_id:$a,model:"claude-haiku-5-5"}],
  triggers:{status_codes:[429,500,502,503,504],on_timeout:true,on_connection_error:true,attempt_timeout_seconds:10}}}')"
ok "if OpenAI fails: try Anthropic claude-haiku-5-5"

step "Act 6: 'Meridian Models', a router: apps ask for a capability, not a vendor"
router="$(ensure model-routers /api/v1/model-routers "Meridian Models" "$(jq -cn --argjson o "$openai" --argjson a "$anthropic" \
  '{name:"Meridian Models",slug:"meridian",description:"Ask for a capability, not a vendor.",api_compat:"openai",active:true,namespace:"",
    pools:[
     {name:"fast",model_pattern:"fast",selection_algorithm:"weighted",priority:20,vendors:[
       {llm_id:$o,weight:80,active:true,mappings:[{source_model:"fast",target_model:"gpt-5.5-mini"}]},
       {llm_id:$a,weight:20,active:true,mappings:[{source_model:"fast",target_model:"claude-haiku-5-5"}]}]},
     {name:"quality",model_pattern:"quality",selection_algorithm:"round_robin",priority:10,vendors:[
       {llm_id:$o,weight:1,active:true,mappings:[{source_model:"quality",target_model:"gpt-5.5"}]},
       {llm_id:$a,weight:1,active:true,mappings:[{source_model:"quality",target_model:"claude-sonnet-5-5"}]}]}]}')")"
put router.meridian.id "$router"
api PUT "/api/v1/model-routers/$router/catalogues" "$(jq -cn --argjson c "[$general]" '{catalogue_ids:$c}')" >/dev/null
ok "router 'meridian' (id $router): fast = 80% OpenAI / 20% Anthropic, quality = round robin; published in General Purpose"
# An app update replaces every field, so the full definition is sent.
api PATCH "/api/v1/apps/$copilot" "$(jq -cn --arg i "$copilot" --argjson u "$dana" --argjson l "[$openai,$anthropic]" --argjson r "[$router]" \
  '{data:{type:"apps",id:$i,attributes:{name:"Claims Copilot",description:"Drafts claim summaries and customer letters for UK claims handlers.",
    user_id:$u,llm_ids:$l,tool_ids:[],datasource_ids:[],model_router_ids:$r,is_active:true}}}')" >/dev/null
ok "Claims Copilot granted the router"
push_config || die "the edges did not come back in sync"
ok "configuration pushed"

step "Act 6: ten calls to meridian/fast at the London edge"
tally="$(for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -sS -D - -o /dev/null "$LONDON_URL/v1/chat/completions" -H "Authorization: Bearer $kc" -H 'Content-Type: application/json' \
    -d '{"model":"meridian/fast","messages":[{"role":"user","content":"Which model are you?"}]}' \
    | awk 'tolower($1)=="x-tyk-served-model:"{print $2}' | tr -d '\r'
done | sort | uniq -c | awk '{printf "%s x %s   ", $2, $1}')"
ok "$tally"

step "Act 6: OpenAI goes down at 10:14"
"$WS_ROOT/scripts/sim.sh" outage openai on >/dev/null
hdr="$(mktemp)"
out="$(curl -sS -D "$hdr" -w '\n%{http_code}' "$LONDON_URL/v1/chat/completions" -H "Authorization: Bearer $kc" -H 'Content-Type: application/json' \
  -d '{"model":"openai/gpt-5.5-mini","messages":[{"role":"user","content":"Draft a short email telling a customer we received their claim."}]}')"
ok "Claims Copilot asks for openai/gpt-5.5-mini -> HTTP $(code_of "$out")"
grep -iE '^x-tyk-(failover|served)' "$hdr" | tr -d '\r' | sed 's/^/  /'; rm -f "$hdr"
"$WS_ROOT/scripts/sim.sh" outage openai off >/dev/null
ok "OpenAI is back; nobody in Claims noticed"
