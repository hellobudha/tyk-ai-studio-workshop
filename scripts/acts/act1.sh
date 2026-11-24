#!/usr/bin/env bash
# Act 1. Monday afternoon. One front door.
# Priya registers the providers once, keeps the vendor keys in AI Studio, prices the
# models, and proves the path with an app of her own.
set -euo pipefail
. "$(dirname "$0")/../lib.sh"
need curl jq
priya="$(must_get user.priya.id)"

step "Act 1: vendor keys become secrets (developers never see them)"
ensure_secret OPENAI_KEY    "sk-sim-openai-MERIDIAN-CONTRACT-KEY"   >/dev/null; ok "secret OPENAI_KEY"
ensure_secret ANTHROPIC_KEY "sk-ant-sim-MERIDIAN-CONTRACT-KEY"      >/dev/null; ok "secret ANTHROPIC_KEY"
ensure_secret HARBOUR_KEY   "hbr-sim-MERIDIAN-INTERNAL-KEY"         >/dev/null; ok "secret HARBOUR_KEY"

step "Act 1: three LLM providers"
openai="$(ensure llms /api/v1/llms "OpenAI" "$(jq -cn '{name:"OpenAI",vendor:"openai",
  api_endpoint:"http://llm-sim:8080/openai/v1",api_key:"$SECRET/OPENAI_KEY",
  default_model:"gpt-5.5-mini",allowed_models:["gpt-5.5","gpt-5.5-mini"],privacy_score:40,active:true,
  short_description:"Public cloud. General-purpose work with no customer data."}')")"
ok "OpenAI (id $openai, privacy score 40)"
anthropic="$(ensure llms /api/v1/llms "Anthropic" "$(jq -cn '{name:"Anthropic",vendor:"anthropic",
  api_endpoint:"http://llm-sim:8080/anthropic/v1",api_key:"$SECRET/ANTHROPIC_KEY",
  default_model:"claude-sonnet-5-5",allowed_models:["claude-sonnet-5-5","claude-haiku-5-5"],privacy_score:40,active:true,
  short_description:"Public cloud. Second supplier, used for drafting and as a fallback."}')")"
ok "Anthropic (id $anthropic, privacy score 40)"
harbour="$(ensure llms /api/v1/llms "Harbour EU" "$(jq -cn '{name:"Harbour EU",vendor:"openai",
  api_endpoint:"http://llm-sim:8080/harbour/v1",api_key:"$SECRET/HARBOUR_KEY",
  default_model:"harbour-large",allowed_models:["harbour-large"],privacy_score:90,active:true,
  short_description:"Self-hosted in Frankfurt. Cleared for customer personal data."}')")"
ok "Harbour EU (id $harbour, privacy score 90, self-hosted)"
put llm.openai.id "$openai"; put llm.anthropic.id "$anthropic"; put llm.harbour.id "$harbour"

step "Act 1: model prices (US dollars per million tokens, input / output)"
ensure_price gpt-5.5           openai    2.50 15.00; ok "gpt-5.5            2.50 / 15.00"
ensure_price gpt-5.5-mini      openai    0.40  2.00; ok "gpt-5.5-mini       0.40 /  2.00"
ensure_price claude-sonnet-5-5 anthropic 3.00 15.00; ok "claude-sonnet-5-5  3.00 / 15.00"
ensure_price claude-haiku-5-5  anthropic 1.00  5.00; ok "claude-haiku-5-5   1.00 /  5.00"
ensure_price harbour-large     openai    0.60  0.60; ok "harbour-large      0.60 /  0.60  (internal chargeback rate)"

step "Act 1: Priya's own app, to prove the path"
app="$(ensure_app "Platform Smoke Test" "Priya's test app: proves a call can travel the governed path." "$priya" \
  "$(jq -cn --argjson a "$openai" --argjson b "$anthropic" --argjson c "$harbour" '{llm_ids:[$a,$b,$c]}')")"
ok "app 'Platform Smoke Test' (id $app), credential active"

step "Act 1: one URL, one key, any provider"
key="$(must_get app.platform-smoke-test.key)"
for m in openai/gpt-5.5-mini anthropic/claude-sonnet-5-5 harbour-eu/harbour-large; do
  out="$(chat "$STUDIO_GW_URL" "$key" "$m" "Which model are you?")"
  code="${out##*$'\n'}"; body="${out%$'\n'*}"
  [ "$code" = 200 ] || die "$m -> HTTP $code: $body"
  ok "$m  ->  $(printf '%s' "$body" | jq -r '.choices[0].message.content')"
done
say ""
say "The provider saw Meridian's contract key, not the app's key:"
curl -sS "$SIM_URL/_sim/requests?last=1" | jq -c '.[0] | {provider, vendor_key_seen}'
