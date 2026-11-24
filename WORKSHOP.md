# One week at Meridian Mutual: the Tyk AI Studio workshop

A hands-on workshop for **Tyk AI Studio Enterprise 2.2.2**. Allow about three hours for the whole week, or
ninety minutes for Acts 0 to 4.

You do not need to know Tyk, and you do not need an LLM provider account. You need the stack running
(`./workshop up`, see the [README](README.md)) and a browser.

## How this workshop works

Each act is one day at Meridian Mutual and follows the same shape:

1. **The situation.** What happened that day and who is asking.
2. **The problem.** Why it is hard without a platform.
3. **What AI Studio does about it.** The idea, in a few lines.
4. **Do it.** The steps in the admin console, as the person in the story.
5. **Prove it.** A command that shows the result from the outside.
6. **What just happened.** The point to take away.

Three habits will help:

- **Catch up any time.** `./workshop act 3` does Act 3 for you through the API, and
  `./workshop goto 3` does Acts 1 to 3. Every act script is safe to run more than once. If you get stuck in
  the console, run the script and compare what it built with what you built.
- **Check yourself.** `./workshop check 3` tells you, line by line, whether Act 3 is in place.
- **Look at the wire.** `./workshop sim seen openai` shows what the (simulated) provider actually received.
  When this guide says "the provider never saw it", that is the command that proves it.
- **Call a model without copying keys.** `./workshop ask <app> <model> "<prompt>"` sends one request through
  the gateway as one of the story's apps and prints the status and the answer. It is a thin wrapper around
  `curl`, and works for any app an act script has run for. The `curl` it stands for is shown in Act 1.

Sign-in details for everyone in the story:

```bash
./workshop who
```

The console is at <http://localhost:8700>. It has three areas, on the tabs at the top: **Chat** (what a
business user sees), **AI Portal** (what a developer sees) and **Administration** (what the platform team
sees). What you see depends on who you are signed in as.

## The cast

| Who | Role | Signs in to |
|---|---|---|
| **Priya Nair** | Head of AI Platform. The administrator. You are Priya most of the time. | Administration |
| **Dana Okafor** | Developer in Claims UK. Wants to ship "Claims Copilot" this sprint. | AI Portal |
| **Tom Reyes** | Claims handler. Does not write code. | Chat |
| **Sofia Keller** | Developer in Claims EU, in the Frankfurt office. | AI Portal |
| **Marcus Bell** | CISO. Owes the regulator an answer by Friday. | Administration (read-only, from Act 7) |
| **Elena Rossi** | FinOps lead. Found a $38,000 line on last quarter's cloud bill that nobody recognised. | Administration (read-only, from Act 7) |

And three model providers. They are simulated on your machine (see the README), but AI Studio treats them
exactly as it would treat the real ones:

| Provider | What it stands for | Models |
|---|---|---|
| **OpenAI** | A public cloud provider | `gpt-5.5`, `gpt-5.5-mini` |
| **Anthropic** | A second public cloud provider | `claude-sonnet-5-5`, `claude-haiku-5-5` |
| **Harbour EU** | Meridian's own model, self-hosted in Frankfurt | `harbour-large` |

---

## Act 0. Monday, 08:40. The incident

### The situation

Tom has forty open claims and a backlog. A colleague shared an OpenAI key that someone put on an expense
card "to try things". Tom pastes a customer's claim into a chatbot to get a summary for the file.

### Do it

```bash
./workshop act 0
```

This act does not touch AI Studio. It sends Tom's prompt straight to the provider, then shows you what the
provider received.

### What just happened

Read the last block of output. The provider received the customer's name, date of birth, National Insurance
number, email address and bank account, sent with a personal key. Now try to answer four questions on
Meridian's behalf:

- Who sent it?
- What did it cost, and whose budget is it on?
- Which model saw it, in which region, under which contract?
- Was anyone allowed to send it?

Nobody at Meridian can answer any of them. That is not a people problem. Tom did something reasonable with
the tools he had. It is a missing piece of infrastructure: **there is no front door**. Every team reaches
every provider directly, with whatever key they can find.

Marcus, the CISO, hears about it at 10:00. By 11:00 the regulator's question is on his desk:
*which models touch customer data, who decided that, and how do you know?* He gives Priya until Friday.

---

## Act 1. Monday afternoon. One front door

### The problem

Meridian has provider keys in at least three places: a shared wiki page, an expense card, and a developer's
`.env` file. There is no list of which models are in use. If a key leaks, it has to be rotated in every
place that copied it, and nobody knows where those places are.

### What AI Studio does about it

AI Studio puts one gateway in front of every model provider.

- The **provider keys live in AI Studio**, as secrets. No developer ever holds one.
- Each team's software gets its own credential, called an **App**. An App's key can be approved, limited,
  measured and revoked on its own.
- Developers call **one OpenAI-compatible endpoint** and name the model as `provider/model`. Moving from
  one provider to another is a one-word change.
- Each provider gets a **privacy level**, a score from 0 to 100 that says how sensitive the data it is
  cleared for can be. It looks like paperwork today. In Act 5 it stops a mistake.

### Do it

Sign in as **Priya** and stay in **Administration**.

**1. Put the provider keys in the vault.** Go to **Settings > Secrets**. A fresh install already lists
`OPENAI_KEY` and `ANTHROPIC_KEY` with no value. Edit each one and give it a value, then add a third:

| Variable name | Value |
|---|---|
| `OPENAI_KEY` | `sk-sim-openai-MERIDIAN-CONTRACT-KEY` |
| `ANTHROPIC_KEY` | `sk-ant-sim-MERIDIAN-CONTRACT-KEY` |
| `HARBOUR_KEY` | `hbr-sim-MERIDIAN-INTERNAL-KEY` |

Do this step first. A provider reads its secret when the provider is saved, so a secret you fill in later
is only picked up the next time you save the provider.

**2. Register the providers.** Go to **LLM management > LLM providers**. A fresh install ships with
entries for `OpenAI` and `Anthropic`. (They normally point at the real vendors. `./workshop up` parked them
on a placeholder address so that nothing can leave your machine.) Open each one (**Actions > Edit**) and
set:

| Field | OpenAI | Anthropic |
|---|---|---|
| Short Description | Public cloud. General-purpose work with no customer data. | Public cloud. Second supplier, used for drafting and as a fallback. |
| Default Model | `gpt-5.5-mini` | `claude-sonnet-5-5` |
| API Endpoint | `http://llm-sim:8080/openai/v1` | `http://llm-sim:8080/anthropic/v1` |
| API Key | `$SECRET/OPENAI_KEY` | `$SECRET/ANTHROPIC_KEY` |
| Privacy level, Score | `40` | `40` |
| Allowed Models | `gpt-5.5`, `gpt-5.5-mini` | `claude-sonnet-5-5`, `claude-haiku-5-5` |

Then **Add LLM provider** for Meridian's own model:

| Field | Harbour EU |
|---|---|
| Name | `Harbour EU` |
| Short Description | Self-hosted in Frankfurt. Cleared for customer personal data. |
| Vendor | OpenAI |
| Default Model | `harbour-large` |
| API Endpoint | `http://llm-sim:8080/harbour/v1` |
| API Key | `$SECRET/HARBOUR_KEY` |
| Privacy level, Score | `90` |
| Allowed Models | `harbour-large` |

Two things to notice. *Vendor* means "which API does this endpoint speak", not "who runs it": Harbour is
Meridian's own model behind an OpenAI-compatible API, so its vendor is OpenAI. And the list now shows the
privacy level as a band: OpenAI and Anthropic are *Internal · 40*, Harbour EU is *Restricted · 90*.

**3. Price the models.** Go to **LLM management > Model prices** and add one row per model. Prices are per
million tokens.

| Model Name | Vendor | Input | Output |
|---|---|---|---|
| `gpt-5.5` | OpenAI | 2.50 | 15.00 |
| `gpt-5.5-mini` | OpenAI | 0.40 | 2.00 |
| `claude-sonnet-5-5` | Anthropic | 3.00 | 15.00 |
| `claude-haiku-5-5` | Anthropic | 1.00 | 5.00 |
| `harbour-large` | OpenAI | 0.60 | 0.60 |

The model name must match what the provider returns, exactly. Without a price row, AI Studio still counts
tokens but records the cost as zero. Harbour's price is an internal chargeback rate: a self-hosted model is
not free, and Elena wants its use to show up next to everything else.

**4. Create an App to prove the path.** Go to **AI Portal > Apps > Add app**.

- Name: `Platform Smoke Test`
- User: Priya Nair
- LLM providers: add OpenAI, Anthropic and Harbour EU
- **Add app**

Open the app. Under **Credential Information** you will see a Key ID and a hidden Secret. If its status is
*Awaiting approval*, choose **Approve this App**. Copy the secret.

### Prove it

Call the gateway that is built into AI Studio. Replace `<secret>` with the secret you copied.

```bash
curl -s http://localhost:8701/v1/chat/completions -H "Authorization: Bearer <secret>" -H "Content-Type: application/json" -d '{"model":"openai/gpt-5.5-mini","messages":[{"role":"user","content":"Which model are you?"}]}' | jq -r '.choices[0].message.content'
```

Change `openai/gpt-5.5-mini` to `anthropic/claude-sonnet-5-5`, then to `harbour-eu/harbour-large`, and run
it again. Same URL, same key, same request format, three providers. The Anthropic call is translated to
Anthropic's own API for you.

If you ran `./workshop act 1`, the shorthand does the same thing without the secret:

```bash
./workshop ask platform-smoke-test anthropic/claude-sonnet-5-5 "Which model are you?"
```

Now look at what the provider saw:

```bash
./workshop sim seen
```

`vendor_key_seen` starts with Meridian's contract key (`hbr-sim-...` for the last call). The App's secret
never left AI Studio.

```bash
./workshop check 1
```

### What just happened

Meridian now has a front door. The provider keys are in one place, encrypted. Software identifies itself
with an App credential that Priya can see, limit and revoke. And there is a single list of which providers
and models the company uses, which is the first thing the regulator will ask for.

If a developer's App secret leaks tomorrow, Priya revokes one App. Nothing else changes.

---

## Act 2. Tuesday. The right doors for the right teams

### The problem

A front door that only Priya can open is a ticket queue. Dana needs model access today to ship Claims
Copilot. But a front door open to everyone is not governance either: the Frankfurt team may use the private
model for EU customer data, and the UK team has no reason to.

### What AI Studio does about it

- A **catalog** is a named collection of providers (and later tools and data sources).
- A **team** is a group of people. A team is given catalogs.
- In the **AI Portal**, a developer sees exactly what their teams' catalogs contain, asks for an App that
  uses some of it, and an administrator approves.

Priya decides once what each team may use. After that, developers serve themselves.

### Do it

Still as **Priya**, in **Administration**.

**1. Make access opt-in.** Go to **Catalogs > LLM catalogs** and edit the `Default` catalog. Remove OpenAI
and Anthropic from it and save. Every new user lands in the Default team, which sees the Default catalog. It
is now empty, so a new joiner sees no models until a team gives them some.

**2. Create two catalogs.** On the same page, **Add catalog** twice:

| Catalog | LLM providers |
|---|---|
| `General Purpose` | OpenAI, Anthropic |
| `EU Resident` | Harbour EU |

**3. Create two teams.** Go to **Access > Teams > Add team**:

| Team name | Members | Catalogs |
|---|---|---|
| `Claims UK` | Dana Okafor, Tom Reyes | General Purpose |
| `Claims EU` | Sofia Keller | General Purpose, EU Resident |

**4. Become Dana.** Sign out (the account menu, top right) and sign in as **Dana**. She lands in the
**AI Portal**. Go to **Browse > All assets**: she sees OpenAI and Anthropic. She does not see Harbour EU,
and nothing she types will find it.

Go to **Apps** and create a new app:

- App Name: `Claims Copilot`
- Description: `Drafts claim summaries and customer letters for UK claims handlers.`
- Add access: OpenAI and Anthropic
- **Create App**

The description matters: the form tells Dana that the administrator who approves the app reads it. The app
now shows as awaiting approval. Its credential exists, and does not work.

**5. Become Priya again and approve.** Sign out, sign in as **Priya**, and go to
**AI Portal > Apps**. `Claims Copilot` shows *Awaiting approval*. Open it, read what Dana asked for, and
choose **Approve this App**.

**6. Back to Dana.** Sign in as Dana and open the app in the portal. Her credential is active, and the page
shows her the endpoint and the model names to use.

### Prove it

```bash
./workshop check 2
```

The last two lines are the point: Claims Copilot can call OpenAI, and the same key is refused for Harbour EU
with a 403, because the App was never granted it.

You can see the earlier refusal too. When Dana tries to request an app that uses Harbour EU, the portal has
nothing to offer her, and the API behind it answers 403. `./workshop act 2` shows that call.

### What just happened

Dana got model access in minutes without holding a provider key, and without Priya writing a policy
document. Priya made two decisions (what is in each catalog, which team gets which catalog) and one approval.
The next ten developers in Claims UK need only the approval.

Notice what did *not* happen: nobody configured "Dana may not use Harbour EU". She cannot use it because
nothing gave it to her. Access here is granted, never assumed.

---

## Act 3. Wednesday. Guardrails

### The situation

Marcus comes to Priya with three rules. They are not negotiable, and he wants them enforced by something
other than a slide in the security training.

1. Customer personal data does not go to a public provider.
2. Credentials do not go to any model.
3. Special Investigations Unit (SIU) case files do not leave Meridian. Fraud investigation notes are legally
   privileged.

### The problem

Rules one and two are the same at every company. Rule three exists only at Meridian. And none of them can
depend on each developer remembering to add a check: Claims Copilot is one app, and there will be fifty.

### What AI Studio does about it

A **filter** runs at the gateway on every request to a provider, before the request leaves. There are two
kinds:

- A **guardrail** needs no code. You pick what to detect (personal data, credentials, prompt injection) and
  what to do about it: **block** the request, **redact** the match and let the rest through, or **log** it.
  AI Studio ships a built-in pattern library, and can also call Lakera, Microsoft Presidio, Azure AI or
  Amazon Bedrock Guardrails.
- A **script** filter is a few lines of code (in a small language called Tengo) for the rules only your
  company has.

Filters attach to a provider. Every App that uses the provider gets them, with no change to any App.

### Do it

As **Priya**, in **Administration**.

**1. Look at what is already there.** Go to **Context management > Filters**. A fresh Enterprise install
ships four guardrails, attached to nothing:

- Credentials in prompts (block)
- Personal data before the vendor (redact)
- Prompt injection heuristics (log)
- Credential leakage in responses (block)

Open *Personal data before the vendor (redact)* and read its settings. It uses the built-in library, the
`pii` detectors, and the action *redact*.

**2. Write Meridian's own rule.** **Add filter**:

- Name: `SIU case files stay inside Meridian`
- Description: `Blocks any prompt that references a Special Investigations Unit case file (SIU-12345).`
- Filter type: **SCRIPT**
- Script: paste the contents of [stack/filters/siu-case-files.tengo](stack/filters/siu-case-files.tengo)

Read the script before you save it. It looks for `SIU-` followed by five digits. If it finds one, it sets
`block` to true, gives the caller a message a human can act on, and records a compliance event of its own.
Use the **Test** panel on the form to try it with a sample message.

**3. Attach all four to the public providers.** Go to **LLM management > LLM providers**, edit **OpenAI**,
and under **Filters** add, in this order:

1. Credentials in prompts (block)
2. Personal data before the vendor (redact)
3. Prompt injection heuristics (log)
4. SIU case files stay inside Meridian

Save, then do the same for **Anthropic**. Leave **Harbour EU** alone: it is self-hosted and cleared for
personal data.

### Prove it

Send Monday's prompt again, this time through the front door, as Dana's app, and look at what the
provider received:

```bash
./workshop ask claims-copilot openai/gpt-5.5-mini @stack/prompts/monday.txt
```

```bash
./workshop sim seen openai
```

Then try a prompt that mentions a fraud case:

```bash
./workshop ask claims-copilot anthropic/claude-sonnet-5-5 "Summarise the investigator notes in SIU-48213 for the customer letter."
```

`./workshop act 3` runs these and two more in one go. Read its output from top to bottom.

- **Monday's prompt.** The handler still gets a summary (HTTP 200). The line in colour is what OpenAI
  received: the date of birth, National Insurance number, email address and bank account are now
  `[REDACTED:...]` placeholders. The policy number, which is not personal data, is still there.
- **A config file with a live key in it.** HTTP 400, *Credentials in prompts (block)*. The request never
  left Meridian.
- **A fraud case.** HTTP 400, with the message from your script.
- **An injection attempt.** HTTP 200. Marcus chose *log* for this one: he wants a week of evidence about
  false positives before he blocks.

Now open **Governance > Compliance overview**. *Claims Copilot* is listed under High Risk Applications, and
the **Filter events** tab shows one event per detection: `guardrail.pii.uk_nino`, `guardrail.pii.iban`,
`guardrail.secrets.aws_access_key`, and your own `meridian.siu_case_reference`. An event records what was
found and what was done. It never stores the matched text.

Then open **AI Portal > Apps > Claims Copilot** and scroll to **Proxy Logs**. The stored request for
Monday's prompt is the redacted one.

```bash
./workshop check 3
```

### What just happened

Compare this with Act 0. The same prompt, the same model, the same answer for the handler. The difference is
what crossed Meridian's boundary.

Dana changed nothing. She did not add a library or a check to Claims Copilot. The next forty-nine apps get
the same rules on the day they are approved, because the rules live on the provider.

A note on honesty. The built-in library finds structured identifiers reliably: National Insurance numbers,
IBANs, card numbers, emails, access keys. It does not know that "Amara Osei" is a person's name. For names
you add a guardrail backed by an entity recogniser such as Microsoft Presidio. It attaches in exactly the
same way.

---

## Act 4. Wednesday night. Money

### The situation

Dana ships a second app before going home: a nightly job that re-summarises open claim files. It has a bug.
When a summary fails validation it retries, and it has no retry limit.

### The problem

Last quarter the same kind of bug cost $38,000 and was discovered by Elena, three weeks later, on an invoice.
A dashboard would not have helped: nobody watches a dashboard at 02:00.

### What AI Studio does about it

AI Studio prices every call as it happens, from the model prices you entered in Act 1, and enforces
**budgets at the gateway**:

- an **App budget**, for one piece of software
- a **provider budget**, a ceiling on everything sent to one provider
- a **team budget**, a monthly pool for all of a team's apps, set to either alert or hard block

When a budget is spent, the next request is refused with HTTP 403. The spend stops.

### Do it

As **Priya**, in **Administration**.

**1. Give the team a pool.** Go to **Access > Teams** and switch on **Team budgets**. Click `Claims UK` to
open its details, choose **Edit budget**, and set:

- Monthly budget: `50`
- Default per new App: `5`
- When exceeded: *Block the team's Apps*

**2. Put a ceiling on the public provider.** Go to **LLM management > LLM providers**, edit **OpenAI**, and
set **Monthly budget** to a fixed amount of `500`.

**3. Give the new job a trial budget.** Go to **AI Portal > Apps > Add app**:

- Name: `Backlog Summariser`
- Description: `Nightly batch job that re-summarises open claim files.`
- User: Dana Okafor
- Team: Claims UK
- LLM providers: OpenAI
- Monthly budget: `1`
- **Add app**, then approve it

One dollar is deliberately small. It is a trial budget for a new job, and it makes the next step quick to
watch.

### Prove it

It is 02:00. Let the bug run.

```bash
./workshop runaway
```

Watch the row of status codes: `200 200 200 ...` and then `403`. Each call sends a 40-page claim file to
`gpt-5.5`, at about six and a half cents a call. After sixteen or seventeen calls the dollar is gone and the
gateway refuses the next one: *Budget limit exceeded: app monthly budget exceeded*.

Two more things are worth checking. The spend is attributed to the **Claims UK** team. And Dana's other
app, Claims Copilot, still answers: one runaway job did not take the team down.

```bash
./workshop ask claims-copilot openai/gpt-5.5-mini "Hello"
```

Open **Analytics** in the console. Under **Cost Analysis** you will find the same numbers in three tables:
LLM Costs (OpenAI against its $500 ceiling), Application Costs (Backlog Summariser at just over 100 percent
of its budget) and Team Costs.

If the job is already over budget and you want to watch it run out again from zero, use
`./workshop act 4 --fresh`. (`./workshop act 4` on its own does steps 1 to 3 and then runs the job.)

```bash
./workshop check 4
```

### What just happened

The bug is the same bug as last quarter. The cost was $1.04 instead of $38,000, and it stopped itself.

Elena also has, for the first time, a cost report she did not have to assemble: every dollar is attached to
an app, an owner and a team, including the self-hosted model.

---

## Act 5. Thursday. Tools and knowledge

### The situation

Tom's team likes the idea of an assistant, but a general-purpose model knows nothing about Meridian. It
cannot tell Tom what the excess is on a storm claim, or whether policy POL-20418 is in force. For that it
needs two things: the claims handbook, and the Policy and Claims system.

### The problem

The Policy and Claims API returns everything about a customer, including their date of birth and bank
account. Connecting it to a model is exactly the kind of decision Marcus has to explain to the regulator.
Three things must be true:

- the customer database is never wired to a public model, even by accident
- a model sees only the fields it needs to answer the question
- an AI agent calling the system is held to the same rules as a person

### What AI Studio does about it

- A **tool** is an internal API, described by its OpenAPI specification, that models and agents may call
  through AI Studio. You choose which operations are allowed. AI Studio holds the API's own key.
- A **data source** is a knowledge base: documents, indexed so a model can be handed the relevant passages.
- Tools and data sources have a **privacy level**, like providers. **A tool or data source can only be used
  with a provider at or above its level.** This is the rule that makes Act 1's scores matter.
- A **chat** puts a provider, tools and data sources together behind a simple chat page for a team.
- The same tool is available to software over **REST** and to AI agents over **MCP**, with the same
  permissions and the same filters.

### Do it

As **Priya**, in **Administration**.

**1. Register the Policy and Claims API as a tool.** Go to **Context management > Tools > Add tool**:

- Name: `Policy and Claims`
- Description: `Look up a Meridian policy or claim by its number. Returns personal data.`
- Tool type: REST API (OpenAPI)
- Privacy level, Score: `80`
- Access methods: switch on **REST API** and **MCP**
- OAS Spec: paste [stack/meridian-api/openapi.json](stack/meridian-api/openapi.json)
- Operations: choose `getPolicy` and `getClaim`
- Authentication Details: Auth Schema Name `ApiKeyAuth`, and for Auth Key the value this command prints

```bash
grep WS_MERIDIAN_API_KEY .env
```

Enter the key itself here. Unlike a provider, a tool in 2.2.2 does not resolve a `$SECRET/` reference for
its upstream key. It is still stored encrypted and never shown again.

**2. Watch the platform refuse a mistake.** Dana would like Claims Copilot to look up policies. Publish the
tool to her team first (step 5 below does this properly; `./workshop act 5` does it for you), then sign in
as **Dana**, go to **AI Portal > Apps**, and create a new app. Under **Add access**, add **OpenAI**, then
open **Tools** and add **Policy and Claims**. Choose **Create App**.

AI Studio refuses:

> Tool "Policy and Claims" requires privacy level 80, but the highest-privacy provider on this app
> ("OpenAI") is at 40. Select a provider with a privacy level of at least 80, or remove the tool.

Cancel the form. Nobody had to remember the rule. The numbers Priya entered on Monday did it. The form
even warns Dana before she tries: *nothing on an app can be more sensitive than its LLM providers are
cleared for*.

**3. Show the model only what it needs.** Go to **Context management > Filters > Add filter**:

- Name: `Policy tool: withhold bank and birth details`
- Filter type: SCRIPT, and switch on **Is this a Response Filter?**
- Script: paste [stack/filters/tool-data-minimisation.tengo](stack/filters/tool-data-minimisation.tengo)

Then edit the **Policy and Claims** tool and add this filter to it. On a tool, a response filter runs on
what the tool returns, before any model or agent sees it. This one replaces `bank_account` and
`date_of_birth` with `[withheld by policy]`.

**4. Turn the handbook into a knowledge base.** Go to **Context management > Data sources > Add data
source**:

- Name: `Claims Handbook`
- User: Priya Nair
- Vector Database Type: `pgvector`
- Embedder: choose **New embedder** and create `Harbour Embeddings`: API compatibility OpenAI, endpoint
  `http://llm-sim:8080/harbour/v1`, API key `$SECRET/HARBOUR_KEY`, model `harbour-embed`, privacy level `90`
- Privacy level, Score: `30` (it is internal guidance with no customer data in it)
- Active: on
- Under **Vector Database Access Details**, Connection String:
  `postgres://studio:<password>@postgres:5432/vectors?sslmode=disable`, with the password from
  `grep WS_POSTGRES_PASSWORD .env`
- Database / Namespace Name: leave it empty (with pgvector in 2.2.2, a name here makes indexing fail)

Save, upload [stack/handbook/claims-handbook.md](stack/handbook/claims-handbook.md) to it, and process the
embeddings. The handbook is embedded by the self-hosted model, so its text never leaves Meridian either.

Create the embedder as a standalone one, as above, and not one linked to the Harbour EU provider. In Act 6
you will move that provider to the EU namespace, and AI Studio refuses to move a provider that a knowledge
base elsewhere depends on.

**5. Publish both to the claims teams.** Create a tool catalog called `Claims Systems` containing the tool
(**Catalogs > Tool catalogs**) and a data catalog called `Claims Knowledge` containing the handbook
(**Catalogs > Data catalogs**). Then edit the teams `Claims UK` and `Claims EU` and add both catalogs to
each.

**6. Build the assistant.** First go to **Chat > Model call settings** and add settings for the model
`harbour-large` (a maximum of `1024` tokens and a temperature of `0.2` are fine). Then go to
**Chat > Chats** and add a chat:

- Name: `Claims Assistant`
- Description: `Ask about a claim, a policy, or the claims handbook.`
- LLM Settings: `harbour-large`
- LLM: **Harbour EU** (the only provider cleared for the tool)
- Teams: Claims UK, Claims EU
- System Prompt: `You are the Meridian Mutual claims assistant. Answer from the claims handbook and the policy system. Be brief and factual.`
- Enable Tool Support: on
- Default Data Source: Claims Handbook
- Default Tools: Policy and Claims

This step is long by hand. `./workshop act 5` does steps 1 to 6 for you and is a fair shortcut here.

**7. Become Tom.** Sign out and sign in as **Tom**. He sees one thing: the Chat area, with *Claims
Assistant* in it. No portal, no administration. Open the chat and ask:

- `What is the excess for a storm damage claim?`
- `Is policy POL-20418 in force?`
- `What is the status of claim CLM-77120?`

For the first question, expand **Retrieved context** to see the handbook passages AI Studio handed to the
model. For the second, the chat shows *Running governance filters* and *Tool result: getPolicy* before the
answer, and the answer ends by saying the bank details and date of birth were withheld.

### Prove it

Sofia in Frankfurt is building an agent that reads a claim and proposes the next action. It needs the same
tool. `./workshop act 5` created her app, *Claims Triage Agent*, with Harbour EU and the tool. This
command talks to the tool the way an agent would, over MCP:

```bash
./workshop mcp
```

- `tools/list` returns `getClaim` and `getPolicy`: the two operations Priya allowed, and nothing else in the
  API.
- `tools/call getPolicy` returns the policy, with `"bank_account": "[withheld by policy]"`. The agent is
  held to the same filter as Tom's chat.

Then look at what the Policy and Claims API itself saw:

```bash
curl -s "http://localhost:8721/_calls?last=1" | jq .
```

It saw AI Studio's key. Neither Tom nor the agent ever held a credential for the system of record.

```bash
./workshop check 5
```

### What just happened

A claims handler can now ask a question in plain language and get an answer grounded in Meridian's own
handbook and its own system of record. That is the useful part.

The governed part is what did not happen. The customer database is not reachable from a public model,
because the platform refuses the combination. The model never saw a bank account, because a filter on the
tool withheld it. And the agent did not get a side door: MCP, REST and chat go through the same permissions
and the same filters.

---

## Act 6. Friday morning. Regions and resilience

### The situation

Two things land on Priya's desk before nine.

Legal confirms what Sofia has been saying: claims data about EU policyholders must be processed inside the
EU. The private model in Frankfurt must not be reachable from anywhere else.

And at 10:14, OpenAI has an outage.

### The problem

Until now every call has gone through the gateway built into AI Studio. That is one process in one place.
Production traffic needs gateways close to the applications, in the right jurisdiction, that keep working if
the control plane is being upgraded. And an app that names one vendor's model stops when that vendor stops.

### What AI Studio does about it

- An **edge gateway** is a small, separate gateway (the Tyk microgateway) that runs wherever you need it.
  AI Studio is the **control plane**: you configure everything there. Edges are the **data plane**: they
  receive their configuration from AI Studio, serve traffic on their own, and send usage and logs back.
- Each edge belongs to a **namespace**. A provider, app or tool can be scoped to a namespace, and then only
  the edges in that namespace receive it. Anything not scoped goes to every edge.
- Changes reach the edges when you **push configuration**. Until then, edges keep serving what they have.
- A provider can have a **failover** list: if it fails, the gateway retries on the next provider, with the
  app's own budget and filters applied to the retry.
- A **model router** lets apps ask for a capability instead of a vendor. The app says `meridian/fast`.
  Priya decides which provider and model that means today.

The workshop stack already runs two edges: `edge-london` in namespace `uk` and `edge-frankfurt` in
namespace `eu`.

### Do it

As **Priya**, in **Administration**.

**1. Meet the edges.** Go to **AI Portal > Edge Gateways**. Both edges are *Connected*. Their Config Sync
is probably *Pending*: you have changed a great deal since they started, and nothing has been pushed.

**2. Scope the private model to the EU.** Go to **LLM management > LLM providers**, edit **Harbour EU**, and
under **Edge Availability** set **Available Namespaces** to `eu`. Save.

**3. Add a failover to OpenAI.** Edit **OpenAI**. Under **Failover**, choose **Add fallback**: Fallback LLM
`Anthropic`, Model `claude-haiku-5-5`. Save. Read the note on that form: an app allowed to use OpenAI is
routed to the fallback when OpenAI fails even if it was never granted Anthropic directly, and budgets still
apply.

**4. Create a router.** Go to **LLM management > Model Routers** and create one:

- Name: `Meridian Models`, Slug: `meridian`, API Compatibility: OpenAI, Active
- Publish in catalogs: General Purpose
- Pool `fast`: model pattern `fast`, weighted. OpenAI with weight 80, mapping `fast` to `gpt-5.5-mini`.
  Anthropic with weight 20, mapping `fast` to `claude-haiku-5-5`.
- Pool `quality`: model pattern `quality`, round robin. OpenAI mapping `quality` to `gpt-5.5`. Anthropic
  mapping `quality` to `claude-sonnet-5-5`.

Then open **AI Portal > Apps > Claims Copilot**, edit it, and add the model router `Meridian Models`.

**5. Push.** Go back to **AI Portal > Edge Gateways** and choose **Push Configuration**. The preview lists
what will change on each edge. Confirm it, and watch Config Sync turn to *Synced* on both.

### Prove it

**Where can Sofia's agent reach Harbour EU?** Ask at each edge.

```bash
./workshop ask claims-triage-agent harbour-eu/harbour-large "Which model are you?" --at london
```

```bash
./workshop ask claims-triage-agent harbour-eu/harbour-large "Which model are you?" --at frankfurt
```

London answers 403 and Frankfurt answers 200. The London gateway was never sent the provider, so there is
no setting on it that could be wrong.

**Ask for a capability.** Send ten calls to `meridian/fast` at the London edge:

```bash
./workshop ask claims-copilot meridian/fast "Which model are you?" --at london --times 10
```

Roughly eight are served by `gpt-5.5-mini` and two by `claude-haiku-5-5`. Claims Copilot named neither.

**Take OpenAI down.** Switch the simulated OpenAI to answer 503, call it, and bring it back:

```bash
./workshop sim outage openai on
```

```bash
./workshop ask claims-copilot openai/gpt-5.5-mini "Draft a short email telling a customer we received their claim." --at london --headers
```

```bash
./workshop sim outage openai off
```

Claims Copilot asked for `openai/gpt-5.5-mini` and got HTTP 200 anyway, with these response headers:

```
X-Tyk-Failover: true
X-Tyk-Served-LLM: anthropic
X-Tyk-Served-Model: claude-haiku-5-5
```

`./workshop act 6` does the whole act, including these calls, in one go.

Every call you made at an edge is in AI Studio's analytics and proxy logs, a few seconds later. The edges
report back on their own.

```bash
./workshop check 6
```

### What just happened

Data residency became a property of the deployment instead of a promise in a policy: the private model
exists on the Frankfurt gateway and nowhere else.

The outage lasted as long as it lasted, and nobody in Claims noticed. The fallback call went through the
same guardrails and counted against the same budget as any other.

And next quarter, when Priya renegotiates with a vendor or a better model appears, she changes a weight in
the router and pushes. No application is redeployed.

---

## Act 7. Friday afternoon. Prove it

### The situation

Marcus has to answer the regulator: *which models touch customer data, who decided that, and how do you
know?*

### The problem

On Monday the honest answer was "we cannot tell". An answer assembled by asking each team is not evidence.
And Marcus should be able to look for himself, without being given the power to change anything.

### What AI Studio does about it

- **Roles.** Enterprise replaces "admin or not" with permissions. It ships five roles: Owner,
  Administrator, Editor, Viewer and Auditor. You can clone them to make your own, and bind them to people or
  whole teams.
- **The audit trail.** Every change made through the console or the API is recorded: who, when, from where,
  what changed field by field, and whether it was allowed. Secrets are redacted.
- **The compliance overview.** Policy blocks, guardrail events, budget alerts and errors, by application.

### Do it

As **Priya**, in **Administration**.

**1. Give the checkers the right roles.** Go to **Access > Users**, edit **Marcus Bell** and give him the
role **Auditor**: read-only access for compliance review, including the audit trail, logs and conversation
transcripts. Edit **Elena Rossi** and give her **Viewer**: configuration and analytics, no sensitive
content.

**2. Become Marcus.** Sign out and sign in as **Marcus**. He now has the Administration area. Try to remove
the filters from the OpenAI provider and save. He cannot: he is missing the permission `llms:write`.

**3. Answer the regulator, as Marcus.**

- *Which models touch customer data?* **LLM management > LLM providers** lists three providers with their
  privacy levels. One is cleared for personal data, and it is the self-hosted one.
- *What stops personal data reaching the others?* Open OpenAI and look at **Filters**: four are attached.
  **Governance > Compliance overview > Filter events** shows them working, with dates and counts.
- *Who decided that?* **Governance > Audit trail**. Filter by Resource *llm*. Expand a row: Priya Nair,
  Wednesday, *Update LLM*, and the field that changed. Marcus's own refused attempt from a minute ago is
  there too, with status 403.
- *Who is using which model?* Open a provider to see its **Models in use** and the apps and owners on each.

Export the audit trail as CSV or JSON from the top of the page. That file is the evidence.

**4. Become Elena.** Sign in as **Elena**. She sees **Analytics** and the cost tables. She cannot open a
prompt: proxy logs need a permission the Viewer role does not have.

### Prove it

```bash
./workshop act 7
```

The script acts as Marcus and Elena. Marcus's attempt to switch off the guardrails returns
`403 missing permission llms:write`. Elena's attempt to read a prompt returns
`403 missing permission proxy-logs:read`. Then Marcus reads the audit summary, and the history of the OpenAI
provider with who changed which fields.

```bash
./workshop check 7
```

### What just happened

Marcus answered the regulator himself, from a record that nobody assembled for the occasion. He could read
everything and change nothing. The people who can change things are named, and everything they changed is
written down.

---

## Friday, 17:00. What changed this week

| | Monday 08:40 | Friday 17:00 |
|---|---|---|
| **Where provider keys live** | A wiki page, an expense card, a `.env` file | AI Studio secrets. No developer holds one. |
| **Who can use which model** | Anyone with a key | Teams and catalogs. Dana asked in the portal and was approved in minutes. |
| **Personal data in prompts** | Sent to a public provider | Redacted at the gateway before it leaves |
| **Secrets and privileged files** | Sent | Blocked, with a message the user can act on |
| **A runaway job** | $38,000, found on an invoice | $1.04, stopped by its budget at 02:00 |
| **The customer database and AI** | Not connected, or connected by whoever tried | A governed tool. The platform refuses to pair it with a public model. |
| **EU data residency** | A paragraph in a policy | The private model exists on the Frankfurt gateway only |
| **A provider outage** | Apps down | Failover to the second provider, same rules applied |
| **"Who decided, and how do you know?"** | Nobody can say | The audit trail, read by the CISO himself |

Nothing in this list required a developer to change how they call a model, beyond the base URL.

## Where to go next

- **Put a real model behind it.** [docs/real-providers.md](docs/real-providers.md) registers a live
  OpenAI or Anthropic model next to the simulated ones in about two minutes.
- **Point a real tool at the gateway.** Any OpenAI-compatible client works. Set its base URL to
  `http://localhost:8711/v1` and its API key to an App secret.
- **Explore what this workshop did not cover.** Semantic routers (route by what the prompt means),
  single sign-on, governed metadata, outbound webhooks, the plugin system and OpenTelemetry metrics are all
  in the same console. The product documentation is in the AI Studio section of <https://tyk.io/docs/>.

## Clean up

```bash
./workshop down
```

stops the stack and keeps your work.

```bash
./workshop reset
```

deletes everything the workshop created.
