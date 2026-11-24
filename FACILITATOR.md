# Facilitator notes

How to run [the workshop](WORKSHOP.md) for a room, or present it as a demo. Unless a line says otherwise,
everything here was observed on Tyk AI Studio Enterprise v2.2.2 on 24 November 2026.

## Before the session

1. **Licence.** Every attendee machine needs a Tyk AI Studio Enterprise licence in `.env`. Check the expiry
   date. An expired licence shows up as `license validation failed ... Token is expired` in
   `./workshop logs studio`, and AI Studio does not start.
2. **Images.** Ask attendees to run `./workshop up` the day before. It pulls about 1.5 GB of images
   (`tykio/tyk-ai-studio-ent`, `tykio/tyk-microgateway-ent`, `pgvector/pgvector:pg16`, `node:22-alpine`).
3. **Ports.** The stack uses 8700, 8701, 8711, 8712, 8720 and 8721 on localhost. Change them in `.env` if
   something else uses one, then `./workshop down && ./workshop up`.
4. **Dry run.** On your own machine: `./workshop reset && ./workshop up && ./workshop goto 7`, then
   `./workshop status`. All seven acts should read *done*. It takes about three minutes.

## Run of show

| Length | What to cover | How |
|---|---|---|
| **9 minutes** | The demo | Play the [video](video/tyk-ai-studio-workshop-demo.mp4), or follow [DEMO.md](DEMO.md) live |
| **45 minutes** | Acts 0 to 3, presenter-led | You drive the console; the room runs the *Prove it* commands |
| **90 minutes** | Acts 0 to 4, hands-on | Attendees do every step. `./workshop goto N` rescues anyone who falls behind |
| **3 hours** | The whole week, hands-on | Break after Act 4. Do Act 5 with `./workshop act 5` plus the chat as Tom |

Suggested timings for the three-hour version:

| Act | Minutes | The one thing the room must see |
|---|---|---|
| 0. The incident | 10 | The provider received the National Insurance number |
| 1. One front door | 25 | Same URL and key, three providers, and the vendor key never left AI Studio |
| 2. Teams and catalogs | 25 | Dana cannot even see Harbour EU, and nobody wrote a rule saying so |
| 3. Guardrails | 25 | Run Act 0's prompt again and compare what the provider received |
| 4. Money | 15 | The row of `200`s ending in `403` |
| *Break* | 15 | |
| 5. Tools and knowledge | 30 | The privacy level refusal, then Tom's chat withholding the bank account |
| 6. Regions and resilience | 25 | London cannot serve Harbour EU; the outage that nobody noticed |
| 7. Prove it | 15 | Marcus's own refused change appears in the audit trail he is reading |

## Telling the story

The workshop works when the room cares about the people before it sees a feature. Three habits help.

- **Open with Act 0, live.** Run `./workshop act 0` and let the room read the provider's view of the prompt
  in silence. Then ask the four questions (who sent it, what did it cost, which model, was it allowed). Do
  not mention Tyk until someone says "so what do you do about it".
- **Name who is asking.** Each act starts with a person and their deadline. "Marcus needs three rules
  enforced by Wednesday" lands better than "now we will configure filters".
- **Close each act by going back to Monday.** Act 3 re-sends Monday's prompt. Act 4 re-runs last quarter's
  bug. Act 7 answers Monday's question. The table at the end of the guide is the summary slide.

Lines that have worked:

- Act 1: "The key your developers hold can no longer reach a model on its own. It can only reach us."
- Act 2: "Nobody wrote 'Dana may not use the private model'. Access here is granted, never assumed."
- Act 3: "Dana changed nothing. The next forty-nine apps get these rules on the day they are approved."
- Act 4: "Same bug as last quarter. A dollar and four cents instead of thirty-eight thousand."
- Act 5: "The numbers Priya typed on Monday just refused to connect the customer database to a public model."
- Act 6: "Data residency stopped being a paragraph in a policy. The model is not on the London gateway."
- Act 7: "He could read everything and change nothing, and his attempt to change something is in the record."

## Questions people ask

**Is the model real?** No. The three providers are a local simulator so the workshop is free, offline and
identical every time. Say so early. AI Studio does not know or care: it speaks the OpenAI and Anthropic wire
formats to them. [docs/real-providers.md](docs/real-providers.md) swaps one for a live model in two
minutes, and it is a good thing to do live if you have a key.

**Does the redaction catch names?** The built-in pattern library finds structured identifiers (National
Insurance numbers, IBANs, cards, emails, access keys) and validates them: it checks the IBAN's check digits,
for example. It does not find free-text names. For that you attach a guardrail backed by Microsoft
Presidio, Azure AI Language, Lakera or Amazon Bedrock Guardrails. Same attachment, different provider.

**What happens to streaming?** Request filters run before anything is sent, so they apply to streamed
calls unchanged. The product documentation says response guardrails re-check a streamed response as it
accumulates and stop the stream on a block. This workshop does not exercise that.

**Does failover bypass the guardrails or the budget?** No. The failover form says it in the console: budgets
are still enforced on the fallback provider, and each fallback attempt goes back through the gateway, so the
fallback provider's own filters apply to it.

**What if the control plane is down?** An edge keeps the configuration it last received. In testing, with
AI Studio stopped, the London edge went on answering for an app that had called it in the previous five
minutes (HTTP 200), and answered 503 for an app it had not seen recently: an edge validates a credential
with the control plane and caches the result for five minutes by default (`EDGE_TOKEN_CACHE_TTL`). Try it:
call the London edge, `docker compose stop studio`, call it again, `docker compose start studio`.

**How is this different from an API gateway?** It understands the payload. It counts tokens and prices
them, reads prompts and tool calls for policy, translates between vendor formats, and routes by model.

## Things that behave in ways you should know about (v2.2.2)

These are observed behaviours, not complaints. Each one has cost a dry run ten minutes.

| What you see | Why | What to do |
|---|---|---|
| A provider sends an empty key upstream after you filled in its secret | The provider resolves `$SECRET/NAME` when the provider is saved, not when the secret changes | Fill in the secret first, or re-save the provider afterwards |
| A tool calls its upstream with the literal text `$SECRET/...` | A tool's Auth Key does not resolve secret references | Enter the key itself on the tool. It is stored encrypted and never displayed |
| Indexing a pgvector data source fails with `add documents failed: unsupported options` | A named collection is passed as an option the pgvector store rejects | Leave **Database / Namespace Name** empty |
| *Reset budget* on an app does not unblock it the same day | The gateway counts spend from the start of the day the period began | Raise the budget, or recreate the app (`./workshop act 4 --fresh`) |
| Moving a provider to a namespace is refused with a message about an embedder | A knowledge base in another namespace embeds with that provider | Use a standalone embedder (the workshop does) |
| A tool filter set to *redact* via a response guardrail only logs | On responses a guardrail is block-only | Use a script filter on the tool to rewrite its output (the workshop does) |
| Through the API, updating a tool or an app wipes fields you did not send | `PATCH` on tools and apps replaces the whole object | Send the full definition. The act scripts do |
| Edges show *Pending* after almost any change | Edges only change when you push | **AI Portal > Edge Gateways > Push Configuration** |
| A brand new edge would call the real vendor endpoints | The default provider entries point at them | `./workshop up` parks them on a placeholder address first |

## Troubleshooting

| Symptom | Check |
|---|---|
| `./workshop up` stops with "AI Studio did not start" | `./workshop logs studio`. Almost always the licence (missing, expired, or pasted with a line break) |
| `MICROGATEWAY_ENCRYPTION_KEY must be exactly 32 characters long` | Someone edited `WS_ENCRYPTION_KEY` in `.env`. Delete its value and run `./workshop up` |
| A port is already in use | Change the port in `.env`, then `./workshop down && ./workshop up` |
| An act script says `missing state ...` | An earlier act has not run. `./workshop goto <n-1>` |
| A call returns 401 at an edge but works on 8701 | The edge has not been pushed to since the app was approved. Push configuration |
| The chat says the user has no access to a data source | The user's team is missing the data catalog (Act 5, step 5) |
| Everything is confused | `./workshop reset && ./workshop up && ./workshop goto <n>` takes three minutes |

## Resetting between sessions

```bash
./workshop reset
```

```bash
./workshop up
```

`reset` removes the containers, the database volume and `.state/`. It keeps `.env`, so the licence and the
generated passwords stay the same and `./workshop who` prints the same sign-in details.
