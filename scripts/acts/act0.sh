#!/usr/bin/env bash
# Act 0. Monday, 08:40. The incident: AI with no front door.
# Nothing here touches AI Studio. It shows the "before" picture.
set -euo pipefail
. "$(dirname "$0")/../lib.sh"
need curl jq

step "Tom pastes a customer's claim into a public chatbot, using a key a colleague put on an expense card"
say "${c_dim}POST $SIM_URL/openai/v1/chat/completions   (straight to the provider)${c_off}"
curl -sS "$SIM_URL/openai/v1/chat/completions" \
  -H 'Authorization: Bearer sk-personal-key-on-an-expense-card' -H 'Content-Type: application/json' \
  -d "$(jq -cn --arg p "$MONDAY_PROMPT" '{model:"gpt-5.5",messages:[{role:"user",content:$p}]}')" \
  | jq -r '.choices[0].message.content'

step "What the provider received"
curl -sS "$SIM_URL/_sim/requests?provider=openai&last=1" | jq '.[0] | {vendor_key_seen, model, prompt: .messages[0].content}'

step "What Meridian knows about that call"
say "  Who sent it?            nobody can say"
say "  What did it cost?       it will be on someone's expenses next month"
say "  Was personal data sent? yes: name, date of birth, NI number, email and bank account"
say "  Which model, which region, which contract terms? unknown"
say ""
say "That is the problem this workshop solves."
