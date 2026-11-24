#!/usr/bin/env bash
# Act 5. Thursday. Giving the model something to work with, safely.
# Meridian's Policy & Claims API becomes a governed tool, the claims handbook becomes
# a knowledge base, and Tom gets a chat assistant that uses both. An agent gets the
# same tool over MCP, under the same rules.
set -euo pipefail
. "$(dirname "$0")/../lib.sh"
need curl jq
priya="$(must_get user.priya.id)"; sofia="$(must_get user.sofia.id)"
openai="$(must_get llm.openai.id)"; harbour="$(must_get llm.harbour.id)"
uk="$(must_get team.uk.id)"; eu="$(must_get team.eu.id)"
general="$(must_get catalogue.general.id)"; private="$(must_get catalogue.eu.id)"

step "Act 5: the Policy & Claims API becomes a governed tool"
# A tool update replaces every field, so the full definition is always sent.
tool="$(ensure tools /api/v1/tools "Policy and Claims" "$(jq -cn --arg s "$(b64 "$WS_ROOT/stack/meridian-api/openapi.json")" --arg k "$WS_MERIDIAN_API_KEY" \
  '{name:"Policy and Claims",description:"Look up a Meridian policy or claim by its number. Returns personal data.",
    tool_type:"REST",oas_spec:$s,privacy_score:80,auth_key:$k,auth_schema_name:"ApiKeyAuth",
    operations:["getPolicy","getClaim"],active:true,rest_access_enabled:true,mcp_access_enabled:true}')")"
put tool.policy.id "$tool"
ok "tool 'Policy and Claims' (id $tool): 2 operations, privacy score 80, upstream key held by AI Studio"

step "Act 5: the platform refuses to wire customer data to a public model"
# Dana asks for a version of her app that can also look up policies.
set +e
msg="$(api POST /api/v1/apps "$(jsonapi apps "$(jq -cn --argjson u "$(must_get user.dana.id)" --argjson l "$openai" --argjson t "$tool" \
  '{name:"Claims Copilot with policy lookup",description:"Claims Copilot plus the Policy and Claims tool.",user_id:$u,llm_ids:[$l],tool_ids:[$t],is_active:true}')")" 2>&1)"
rc=$?
set -e
if [ $rc -ne 0 ] && printf '%s' "$msg" | grep -q "Privacy Score Mismatch"; then
  ok "an app that pairs the tool with OpenAI is refused:"
  say "  ${c_cyan}$(printf '%s' "$msg" | sed 's/^.*"detail":"//; s/"}.*$//; s/\\"/"/g')${c_off}"
else
  warn "expected a privacy score refusal, got: $msg"
  stray="$(id_by_name /api/v1/apps "Claims Copilot with policy lookup")"; [ -n "$stray" ] && api DELETE "/api/v1/apps/$stray" >/dev/null
fi

step "Act 5: the model only sees the fields it needs"
minim="$(ensure_script_filter "Policy tool: withhold bank and birth details" \
  "Removes the bank account and date of birth from what the Policy and Claims tool returns, before a model or an agent sees it." \
  "$WS_ROOT/stack/filters/tool-data-minimisation.tengo" true)"
api PUT "/api/v1/tools/$tool/filters" "$(jq -cn --argjson f "[$minim]" '{data:{type:"tools",attributes:{filters:$f}}}')" >/dev/null 2>&1 \
  || api POST "/api/v1/tools/$tool/filters/$minim" >/dev/null
ok "response filter attached to the tool (id $minim)"

step "Act 5: the claims handbook becomes a knowledge base"
# A standalone embedder (its own endpoint and key) rather than one linked to the Harbour EU provider,
# so that provider can be moved to the EU namespace in Act 6 without touching the knowledge base.
emb="$(ensure embedders /api/v1/embedders "Harbour Embeddings" "$(jq -cn \
  '{name:"Harbour Embeddings",description:"Embeddings on the self-hosted model, so handbook text never leaves Meridian.",
    vendor:"openai",endpoint:"http://llm-sim:8080/harbour/v1",api_key:"$SECRET/HARBOUR_KEY",model:"harbour-embed",privacy_score:90}')")"
ok "embedder 'Harbour Embeddings' (id $emb)"
# The collection name is left empty: with pgvector in 2.2.2 a named collection is rejected at indexing time.
ds="$(ensure datasources /api/v1/datasources "Claims Handbook" "$(jq -cn --argjson e "$emb" --argjson u "$priya" \
  --arg c "postgres://studio:$WS_POSTGRES_PASSWORD@postgres:5432/vectors?sslmode=disable" \
  '{name:"Claims Handbook",short_description:"Meridian claims handling guidance. No customer data.",privacy_score:30,user_id:$u,
    db_source_type:"pgvector",db_conn_string:$c,db_name:"",embedder_id:$e,active:true}')")"
put datasource.handbook.id "$ds"
if [ "$(api GET "/api/v1/datasources/$ds" | jq '.data.attributes.files | length')" = 0 ]; then
  fs="$(curl -sS -X POST "$STUDIO_URL/api/v1/filestore" -H "Authorization: Bearer $(must_get admin.key)" \
    -F "file=@$WS_ROOT/stack/handbook/claims-handbook.md" -F "description=Claims handbook extract" | jq -r .data.id)"
  api POST "/api/v1/datasources/$ds/filestores/$fs" >/dev/null
  api POST "/api/v1/datasources/$ds/process-embeddings" >/dev/null
  sleep 5
  ok "handbook uploaded and indexed (id $ds, privacy score 30)"
else
  ok "handbook already indexed (id $ds)"
fi

step "Act 5: catalogs, so teams can find them"
tc="$(id_by_name /api/v1/tool-catalogues "Claims Systems")"
[ -n "$tc" ] || tc="$(api POST /api/v1/tool-catalogues "$(jsonapi tool-catalogues '{"name":"Claims Systems","short_description":"Governed access to Meridian claims systems."}')" | jq -r .data.id)"
api POST "/api/v1/tool-catalogues/$tc/tools" "$(jq -cn --arg i "$tool" '{data:{type:"tools",id:$i}}')" >/dev/null 2>&1 || true
dc="$(id_by_name /api/v1/data-catalogues "Claims Knowledge")"
[ -n "$dc" ] || dc="$(api POST /api/v1/data-catalogues "$(jsonapi data-catalogues '{"name":"Claims Knowledge","short_description":"Handbooks and guidance for claims handlers."}')" | jq -r .data.id)"
api POST "/api/v1/data-catalogues/$dc/datasources" "$(jq -cn --arg i "$ds" '{data:{type:"datasources",id:$i}}')" >/dev/null 2>&1 || true
grant() { api PUT "/api/v1/groups/$1/catalogues" "$(jq -cn --argjson c "$2" --argjson d "[$dc]" --argjson t "[$tc]" \
  '{data:{type:"groups",attributes:{catalogues:$c,data_catalogues:$d,tool_catalogues:$t}}}')" >/dev/null; }
grant "$uk" "[$general]"; grant "$eu" "[$general,$private]"
ok "tool catalog 'Claims Systems' and data catalog 'Claims Knowledge' given to both claims teams"

step "Act 5: a chat assistant for claims handlers"
sid="$(api GET "/api/v1/llm-settings?all=true&page_size=200" | jq -r '[.data[]|select(.attributes.model_name=="harbour-large")|.id][0] // empty')"
[ -n "$sid" ] || sid="$(api POST /api/v1/llm-settings "$(jsonapi llm-settings '{"model_name":"harbour-large","max_tokens":1024,"max_length":32000,"temperature":0.2}')" | jq -r .data.id)"
chat="$(ensure chats /api/v1/chats "Claims Assistant" "$(jq -cn --argjson l "$harbour" --argjson s "$sid" --argjson t "$tool" --argjson d "$ds" --argjson g "[$uk,$eu]" \
  '{name:"Claims Assistant",description:"Ask about a claim, a policy, or the claims handbook.",llm_id:$l,llm_settings_id:$s,group_ids:$g,
    tool_support:true,rag_n:2,default_data_source_id:$d,default_tool_ids:[$t],
    system_prompt:"You are the Meridian Mutual claims assistant. Answer from the claims handbook and the policy system. Be brief and factual."}')")"
put chat.claims.id "$chat"
ok "chat 'Claims Assistant' (id $chat) on Harbour EU, with the handbook and the tool, for Claims UK and Claims EU"
say "  Sign in as Tom and try it: $STUDIO_URL/chat/$chat"

step "Act 5: the same tool for an agent, over MCP"
agent="$(ensure_app "Claims Triage Agent" "Sofia's agent: reads a claim and proposes the next action." "$sofia" \
  "$(jq -cn --argjson l "$harbour" --argjson t "$tool" --argjson g "$eu" '{llm_ids:[$l],tool_ids:[$t],team_id:$g}')")"
key="$(must_get app.claims-triage-agent.key)"
ok "app 'Claims Triage Agent' (id $agent): Harbour EU + Policy and Claims"
H=(-H "Authorization: Bearer $key" -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream')
mcp="$STUDIO_GW_URL/tools/policy-and-claims/mcp"
hdr="$(mktemp)"
curl -sS -D "$hdr" -o /dev/null "$mcp" "${H[@]}" -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"claims-triage-agent","version":"1.0"}}}'
sess="$(awk 'tolower($1)=="mcp-session-id:"{print $2}' "$hdr" | tr -d '\r')"; rm -f "$hdr"
S=(); [ -n "$sess" ] && S=(-H "Mcp-Session-Id: $sess")
names="$(curl -sS "$mcp" "${H[@]}" "${S[@]}" -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | jq -r '[.result.tools[].name]|join(", ")')"
ok "MCP tools/list -> $names"
res="$(curl -sS "$mcp" "${H[@]}" "${S[@]}" -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"getPolicy","arguments":{"policy_id":"POL-20418"}}}' | jq -r '.result.content[0].text')"
ok "MCP tools/call getPolicy -> holder $(printf '%s' "$res" | jq -r .holder), bank account: $(printf '%s' "$res" | jq -r .bank_account)"
say ""
say "What the Policy & Claims API saw: AI Studio's key, never the agent's."
curl -sS "$MERIDIAN_URL/_calls?last=1" | jq -c '.[0]'
