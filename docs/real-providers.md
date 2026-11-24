# Putting a real model behind the workshop

The workshop uses simulated providers so that it is free, offline and repeatable. Nothing about AI Studio's
configuration is special to the simulator. To see the same governance in front of a live model, register a
real provider next to the simulated ones. It takes about two minutes.

A real provider costs money per call and sends your prompts to that vendor. Use a key with a low spend
limit, and do not send it anything you would not send to that vendor directly.

## OpenAI

Sign in as Priya, in **Administration**.

1. **Settings > Secrets > Add secret.** Variable name `OPENAI_LIVE_KEY`, value: your OpenAI API key.
2. **LLM management > LLM providers > Add LLM provider.**

   | Field | Value |
   |---|---|
   | Name | `OpenAI Live` |
   | Vendor | OpenAI |
   | Default Model | a model your key can use |
   | API Endpoint | `https://api.openai.com/v1` |
   | API Key | `$SECRET/OPENAI_LIVE_KEY` |
   | Privacy level, Score | `40` |
   | Allowed Models | the same model |
   | Filters | the four filters from Act 3 |
   | Monthly budget | `2` |

3. **LLM management > Model prices.** Add a row for that model with the vendor's current price per million
   tokens, so that cost and budgets are right.
4. **Catalogs > LLM catalogs.** Add `OpenAI Live` to `General Purpose`.
5. **AI Portal > Apps.** Edit `Platform Smoke Test` and add `OpenAI Live`.

Call it. The provider's name becomes the first part of the model string, in lower case with dashes:

```bash
curl -s http://localhost:8701/v1/chat/completions -H "Authorization: Bearer <Platform Smoke Test secret>" -H "Content-Type: application/json" -d '{"model":"openai-live/<model>","messages":[{"role":"user","content":"In one sentence, what is an insurance excess?"}]}' | jq -r '.choices[0].message.content'
```

Everything from the workshop applies to it at once: the guardrails you attached redact and block before the
request leaves, the $2 budget stops it, the call is priced, logged and attributed, and Marcus can see who
added it in the audit trail.

## Anthropic

The same steps with Vendor *Anthropic*, API Endpoint `https://api.anthropic.com/v1`, and a Claude model
your key can use. Clients still call it in the OpenAI format on `/v1/chat/completions`. AI Studio
translates.

## Sending real traffic through an edge

Push configuration (**AI Portal > Edge Gateways > Push Configuration**), then use the London edge instead of
the built-in gateway by changing the port from `8701` to `8711`.

## Using it from a real tool

Any OpenAI-compatible client or SDK works. Point it at the gateway and give it an App secret:

```bash
export OPENAI_BASE_URL=http://localhost:8711/v1
```

```bash
export OPENAI_API_KEY=<an App secret>
```

Then ask for the model as `provider/model`, for example `openai-live/<model>` or `meridian/fast`.

## Going back

Delete the provider, or set it to inactive. The simulated providers are untouched.
