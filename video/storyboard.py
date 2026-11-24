#!/usr/bin/env python3
"""The demo video's storyboard, in one place.

Running this file writes one folder per take under video/work/takes/:
  - a terminal take gets scene.json  (replayed by termcast.py: real commands, real output)
  - a web take gets steps.json       (replayed by the Playwright web recorder in real Chromium)
  - every take gets story.tsv        (cards, subtitles and the spoken narration)
  - prep.sh, when the take needs something done off camera first (for example ./workshop act 3)

record.sh then records each take against the live workshop stack and joins them.

Reading time is worked out from the narration: each beat is held long enough for its line to be
spoken at a natural pace, so the voice is never sped up to fit.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "work", "takes")
BASE = "http://localhost:8700"
WPS = 2.0           # spoken words per second we plan for (the macOS "Daniel" voice measures about 2.2)

PEOPLE = {
    "priya": ("priya.nair@meridian-mutual.example", "$env:WS_ADMIN_PASSWORD"),
    "dana": ("dana.okafor@meridian-mutual.example", "$env:WS_USER_PASSWORD"),
    "tom": ("tom.reyes@meridian-mutual.example", "$env:WS_USER_PASSWORD"),
    "marcus": ("marcus.bell@meridian-mutual.example", "$env:WS_USER_PASSWORD"),
}


def card(name, seconds, title, body, spoken):
    return {"kind": "card", "name": name, "seconds": seconds, "line1": title, "line2": body, "spoken": spoken}


def beat(name, sub1, sub2, spoken, actions):
    return {"kind": "beat", "name": name, "line1": sub1, "line2": sub2, "spoken": spoken, "actions": actions}


# --- small helpers for web actions -------------------------------------------------------------
def goto(url): return {"do": "goto", "url": url}
def hl(target, seconds=3): return {"do": "highlight", "target": target, "seconds": seconds}
def click(target): return {"do": "click", "target": target}
def typ(target, text): return {"do": "type", "target": target, "text": text, "delay": 35}
def expect(text): return {"do": "expect", "text": text, "timeout": 30000}
def wait_for(target): return {"do": "waitFor", "target": target, "timeout": 30000}
def pause(seconds): return {"do": "pause", "seconds": seconds}
def scroll(target): return {"do": "scroll", "target": target}
def press(key, target=None): return {"do": "press", "key": key, **({"target": target} if target else {})}


def show(cmd, **kw): return {"show": cmd, **kw}
def banner(text): return {"banner": text}


ASK = "./workshop ask"

TAKES = [
    # ------------------------------------------------------------------------------- Monday 08:40
    dict(id="01-incident", kind="term", story=[
        card("intro", 12, "One week at Meridian Mutual",
             "Tyk AI Studio Enterprise 2.2.2|Model providers are simulated locally|A governed front door for AI",
             "Meridian Mutual is an insurer with four thousand staff. This is the week it took control of A I, "
             "using Tyk A I Studio. The model providers in this demo are simulated. A I Studio is the real product."),
        card("monday", 9, "Monday, 08:40", "The incident",
             "Monday morning. Tom, a claims handler, pastes a customer's claim into a public chatbot, "
             "using a key a colleague put on an expense card."),
        beat("b1", "Tom sends a customer's claim straight to a public provider", "",
             "The request goes straight to the provider, and Tom gets his summary.",
             [show('curl -s $PROVIDER/openai/v1/chat/completions -H "Authorization: Bearer $EXPENSE_CARD_KEY" '
                   '-H "Content-Type: application/json" -d @stack/prompts/monday.json | jq -r ".choices[0].message.content"',
                   must_show=["Claim summary"])]),
        beat("b2", "What the provider received", "date of birth, NI number, email, bank account",
             "But look at what the provider received. The customer's date of birth, National Insurance number, "
             "email address and bank account. Nobody at Meridian can say who sent it, what it cost, "
             "or whether it was allowed. The regulator wants an answer by Friday.",
             [show("./workshop sim seen openai", must_show=["AB 12 34 56 C", "GB29"])]),
    ]),
    # ------------------------------------------------------------------------------- Monday pm
    dict(id="02-front-door", kind="web", user="priya", prep="./workshop act 1", story=[
        card("act1", 9, "Monday afternoon", "One front door",
             "Priya runs the A I platform team. Her first move is to put one front door in front of every model."),
        beat("b1", "Three providers, registered once", "each with a privacy level",
             "She registers the providers once. Two public clouds, and Meridian's own model in Frankfurt. "
             "Each gets a privacy level that says how sensitive its data can be.",
             [goto("/admin/llms"), wait_for("text=Harbour EU"), hl("table", 5)]),
        beat("b2", "Provider keys live in AI Studio, as secrets", "",
             "The provider keys live here, as secrets. No developer ever holds one.",
             [goto("/admin/secrets"), wait_for("text=OPENAI_KEY"), hl("table", 3)]),
        beat("b3", "Software gets its own credential: an App", "",
             "Instead, each piece of software gets its own credential, called an app, "
             "which Priya can approve, limit and revoke.",
             [goto("/admin/apps"), wait_for("text=Platform Smoke Test"), click("text=Platform Smoke Test"),
              wait_for("text=Credential Information"), scroll("text=Credential Information"),
              hl("text=Credential Information", 3)]),
    ]),
    dict(id="03-one-endpoint", kind="term", story=[
        beat("b1", "One URL, one key, three providers", "",
             "Developers call one endpoint and name the model they want. "
             "Same address, same key, three different providers.",
             [show(f'{ASK} platform-smoke-test openai/gpt-5.5-mini "Which model are you?"', must_show=["HTTP 200"]),
              show(f'{ASK} platform-smoke-test anthropic/claude-sonnet-5-5 "Which model are you?"', must_show=["HTTP 200"]),
              show(f'{ASK} platform-smoke-test harbour-eu/harbour-large "Which model are you?"', must_show=["HTTP 200"])]),
        beat("b2", "The provider saw Meridian's key, not the app's", "",
             "And the provider only ever sees Meridian's contract key. The app's own key never leaves the building.",
             [show("./workshop sim seen | jq '{provider, vendor_key_seen, model}'", must_show=["hbr-sim"])]),
    ]),
    # ------------------------------------------------------------------------------- Tuesday
    dict(id="04-self-service", kind="web", user="dana", prep="./workshop act 2 --setup-only", story=[
        card("act2", 11, "Tuesday", "The right doors for the right teams",
             "Tuesday. Dana, a developer in the U K claims team, needs model access today. "
             "Priya has published the providers in catalogs, and given each team its catalogs."),
        beat("b1", "Dana sees only what her team was given", "",
             "In the A I portal, Dana sees the two public models her team was given. "
             "Meridian's private model is not on her list.",
             [goto("/portal/catalog"), wait_for("text=Anthropic"), hl("main", 4)]),
        beat("b2", "She asks for an app, in her own words", "",
             "She asks for an app, says what it is for, and picks the models it needs.",
             [goto("/portal/app/new"), wait_for('role=button[name="Add OpenAI"]'),
              typ("role=textbox[name=/App Name/]", "Claims Copilot"),
              typ("role=textbox[name=/Description/]", "Drafts claim summaries and customer letters for UK claims handlers."),
              click('role=button[name="Add OpenAI"]'), click('role=button[name="Add Anthropic"]'),
              click('role=button[name="Create App"]')]),
        beat("b3", "The request waits for approval", "",
             "The request goes to Priya. Until she approves it, the key does not work.",
             [goto("/portal/apps"), wait_for("text=Claims Copilot"), hl("main", 3)]),
    ]),
    dict(id="05-approve", kind="web", user="priya", after="./workshop act 2", story=[
        beat("b1", "Priya reviews the request", "",
             "Priya sees the request, with Dana's description.",
             [goto("/admin/apps"), wait_for("text=Awaiting approval"), hl('tr:has-text("Claims Copilot")', 3)]),
        beat("b2", "One click to approve", "",
             "One click, and Dana has a working key. No ticket, and no provider key changed hands.",
             [click("text=Claims Copilot"), wait_for('role=button[name="Approve this App"]'),
              click('role=button[name="Approve this App"]'), pause(2),
              scroll("text=Credential Information"), hl("text=Credential Information", 3)]),
    ]),
    # ------------------------------------------------------------------------------- Wednesday
    dict(id="06-guardrails", kind="web", user="priya", prep="./workshop act 3", story=[
        card("act3", 12, "Wednesday", "Guardrails",
             "Wednesday. Marcus, the chief information security officer, has three rules. "
             "No personal data to public providers. No credentials to any model. "
             "And fraud investigation files never leave Meridian."),
        beat("b1", "Built-in guardrails, plus one rule only Meridian could write", "",
             "A I Studio ships with guardrails for personal data, credentials and prompt injection. "
             "Priya adds one rule of Meridian's own, as a short script.",
             [goto("/admin/filters"), wait_for("text=SIU case files stay inside Meridian"), hl("table", 5)]),
        beat("b2", "Attached to the provider, so every app is covered", "",
             "She attaches them to the public providers. Every app that uses those providers is now covered, "
             "without changing a line of anyone's code.",
             [goto("/admin/llms/edit/1"), wait_for("text=Update LLM provider"),
              click('main .MuiAccordionSummary-root:has-text("Filters")'),
              wait_for("text=Filters added here are executed"),
              hl('main .MuiAccordion-root:has-text("Filters added here are executed")', 5)]),
    ]),
    dict(id="07-guardrails-proof", kind="term", story=[
        beat("b1", "Monday's prompt again, through the front door", "the provider now receives placeholders",
             "Here is Monday's prompt again, sent through the front door. The handler still gets a summary. "
             "But this is what the provider received this time. The date of birth, the National Insurance number, "
             "the email and the bank account are gone.",
             [show(f"{ASK} claims-copilot openai/gpt-5.5-mini @stack/prompts/monday.txt", must_show=["HTTP 200"]),
              show("./workshop sim seen openai | jq -r '.messages[0].content'", must_show=["REDACTED:UK_NINO", "REDACTED:IBAN"])]),
        beat("b2", "A fraud case file is stopped, with a reason", "",
             "And a prompt that mentions a fraud case file is stopped at the gateway, "
             "with a message the person can act on.",
             [show(f'{ASK} claims-copilot anthropic/claude-sonnet-5-5 "Summarise the investigator notes in SIU-48213 for the customer letter."',
                   must_show=["HTTP 400", "SIU case files"])]),
    ]),
    dict(id="08-compliance", kind="web", user="priya", story=[
        beat("b1", "Every detection is a compliance event", "what was found and what was done, never the data",
             "Every detection is recorded as a compliance event. What was found, in which app, "
             "and what was done about it. Never the data itself.",
             [goto("/admin/compliance"), wait_for("text=High Risk Applications"), hl("text=High Risk Applications", 2),
              scroll("role=tab[name=/filter events/i]"), click("role=tab[name=/filter events/i]"), pause(2)]),
    ]),
    # ------------------------------------------------------------------------------- Wednesday night
    dict(id="09-budget", kind="term", prep="./workshop act 4 --setup-only", story=[
        card("act4", 12, "Wednesday night", "Money",
             "Wednesday night. Dana ships a nightly batch job with a bug. It retries forever. "
             "Last quarter a bug like this cost thirty eight thousand dollars, and finance found it on the invoice."),
        beat("b1", "02:00. The job loops. Its budget is one dollar.", "",
             "This time the job has a one dollar trial budget. It runs, and runs, "
             "and then the gateway refuses it. The spend stops at about a dollar.",
             [show("./workshop runaway", must_show=["403", "Budget limit exceeded"], timeout=240)]),
    ]),
    dict(id="10-costs", kind="web", user="priya", story=[
        beat("b1", "Every dollar has an app, an owner and a team", "",
             "Elena in finance did not have to assemble anything. "
             "Every dollar is attached to an app, an owner and a team.",
             [goto("/admin/dash"), wait_for("text=Application Costs"), scroll("text=Application Costs"),
              hl("text=Backlog Summariser", 3), scroll("text=Model and Tool Usage"),
              hl('tr:has-text("Claims UK")', 3)]),
    ]),
    # ------------------------------------------------------------------------------- Thursday
    dict(id="11-tool-refusal", kind="web", user="dana", prep="./workshop act 5", story=[
        card("act5", 11, "Thursday", "Tools and knowledge",
             "Thursday. An assistant is only useful if it knows Meridian. Priya registers the internal policy system "
             "as a governed tool, and the claims handbook as a knowledge base."),
        beat("b1", "The platform refuses to connect customer data to a public model", "",
             "Dana tries to give her app the policy tool, next to a public model. A I Studio refuses. "
             "The tool holds personal data, and that provider is not cleared for it. "
             "The privacy levels Priya set on Monday just prevented a mistake.",
             [goto("/portal/app/new"), wait_for('role=button[name="Add OpenAI"]'),
              typ("role=textbox[name=/App Name/]", "Claims Copilot with policy lookup"),
              typ("role=textbox[name=/Description/]", "Claims Copilot plus the Policy and Claims tool."),
              click('role=button[name="Add OpenAI"]'), click("#app-access-tab-tool"),
              click('role=button[name="Add Policy and Claims"]'), click('role=button[name="Create App"]'),
              expect("requires privacy level 80"), hl("text=requires privacy level 80", 5)]),
    ]),
    dict(id="12-chat", kind="web", user="tom", story=[
        beat("b1", "Tom asks the claims handbook", "",
             "Tom, the claims handler, gets a chat assistant that runs on Meridian's own model. "
             "He asks about the handbook, and the answer comes from Meridian's own document.",
             [goto("/chat/dashboard"), wait_for("text=Claims Assistant"), click("text=Start chat"),
              wait_for('role=textbox[name="Message"]'),
              typ('role=textbox[name="Message"]', "What is the excess for a storm damage claim?"), press("Enter"),
              # the same sentence also sits in the collapsed "Retrieved context" block, so match the answer itself
              expect("According to the claims handbook"), hl('p:has-text("According to the claims handbook")', 4)]),
        beat("b2", "A live policy lookup, with bank details withheld", "",
             "He asks about a policy. The assistant calls the policy system, and a filter on the tool withholds "
             "the bank account and date of birth before the model ever sees them.",
             [typ('role=textbox[name="Message"]', "Is policy POL-20418 in force?"), press("Enter"),
              expect("withheld from me by policy"), hl("text=withheld from me by policy", 4)]),
    ]),
    dict(id="13-mcp", kind="term", story=[
        beat("b1", "The same tool for an AI agent, over MCP", "same permissions, same filter",
             "An A I agent gets the same tool over M C P, with the same permissions and the same filter. "
             "There is no side door.",
             [show("./workshop mcp", must_show=["getClaim", "withheld by policy"])]),
    ]),
    # ------------------------------------------------------------------------------- Friday am
    dict(id="14-edges", kind="web", user="priya", prep="./workshop act 6", story=[
        card("act6", 11, "Friday morning", "Regions and resilience",
             "Friday morning. Legal confirms that E U customer data must be processed in the E U. "
             "And at fourteen minutes past ten, a provider has an outage."),
        beat("b1", "Two edge gateways, configured from one place", "",
             "Traffic now runs through edge gateways in London and Frankfurt. "
             "They are configured from A I Studio, and they report back to it.",
             [goto("/admin/edge-gateways"), wait_for("text=edge-frankfurt"), hl("table", 5)]),
    ]),
    dict(id="15-resilience", kind="term", story=[
        beat("b1", "The private model exists in Frankfurt only", "",
             "Priya scopes the private model to the E U. The London gateway refuses it, "
             "because it was never given that provider. Frankfurt serves it.",
             [show(f'{ASK} claims-triage-agent harbour-eu/harbour-large "Which model are you?" --at london', must_show=["HTTP 403"]),
              show(f'{ASK} claims-triage-agent harbour-eu/harbour-large "Which model are you?" --at frankfurt', must_show=["HTTP 200"])]),
        {"clear": True},
        beat("b2", "A provider goes down. The app does not notice.", "",
             "Then the outage. Dana's app asks for its usual model, and still gets an answer. "
             "The gateway failed over to the second provider, with the same guardrails and the same budget.",
             [show("./workshop sim outage openai on"),
              show(f'{ASK} claims-copilot openai/gpt-5.5-mini "Draft a short email telling a customer we received their claim." --at london --headers',
                   must_show=["HTTP 200", "X-Tyk-Failover: true"]),
              show("./workshop sim outage openai off")]),
        {"clear": True},
        beat("b3", "Apps ask for a capability. Priya picks the vendor.", "",
             "Better still, apps can ask for a capability, like fast, and let Priya decide which vendor answers. "
             "Changing supplier is now a setting, not a release.",
             [show(f'{ASK} claims-copilot meridian/fast "Which model are you?" --at london --times 10', must_show=["served by"])]),
    ]),
    # ------------------------------------------------------------------------------- Friday pm
    dict(id="16-prove-it", kind="web", user="marcus", prep="./workshop act 7", story=[
        card("act7", 11, "Friday afternoon", "Prove it",
             "Friday afternoon. The regulator asked which models touch customer data, who decided, "
             "and how Meridian knows. Marcus can now answer that himself."),
        beat("b1", "The audit trail: who, when, what, and whether it was allowed", "",
             "He has a read only role. The audit trail shows every change to the provider. Who made it, when, "
             "and whether it was allowed. His own refused attempt to change it is there too.",
             [goto("/admin/audit"), wait_for('role=textbox[name="Search"]'),
              typ('role=textbox[name="Search"]', "OpenAI"), click('role=button[name="Apply filters"]'), pause(1.5),
              scroll("table"), hl("table", 5)]),
        beat("b2", "Each change, field by field", "",
             "Each change is recorded field by field. This is evidence that nobody had to assemble.",
             [click('table tbody tr:has-text("priya.nair") >> role=button[name="expand"] >> nth=0'),
              wait_for("text=Changed fields"), scroll("text=Changed fields"), {"do": "scroll", "y": 300},
              hl("text=Changed fields", 4)]),
        card("friday", 17, "Friday, 17:00",
             "Provider keys in one place|Access by team|Personal data redacted|Spend capped|"
             "Tools governed|Residency enforced|Every change on the record",
             "One week. Provider keys in one place. Access by team. Personal data redacted before it leaves. "
             "Spend capped. Tools governed. Residency enforced. And every change on the record. "
             "No developer changed how they call a model, beyond one address."),
        card("end", 8, "Try it yourself", "The whole week runs on your laptop|./workshop up",
             "The whole week runs on your laptop with one command. The workshop guide is in this repository."),
    ]),
]


# --- how long things take on screen, so each beat can be held for its narration -----------------
def web_seconds(a):
    d = a["do"]
    if d == "goto": return 1.6
    if d == "highlight": return a.get("seconds", 2) + 0.4
    if d == "pause": return a.get("seconds", 1)
    if d == "type": return len(a["text"]) * 0.04 + 0.8
    if d in ("waitFor", "expect"): return 0.4
    return 0.7


def term_seconds(a):
    if "show" in a: return len(a["show"]) / 45 + 0.5 + 0.5 + 1.2
    if "banner" in a: return 0.8
    return 0.3


def words(t): return len(t.split())


def main():
    # Only the plans are rewritten: recordings already in a take's folder are left alone,
    # so single takes can be re-recorded (ONLY=... NO_RESET=1 video/record.sh).
    for take in TAKES:
        d = os.path.join(OUT, take["id"])
        os.makedirs(d, exist_ok=True)
        steps, rows = [], ["# kind\tname\tseconds\tline1\tline2\tspoken"]
        for item in take["story"]:
            if "clear" in item:
                steps.append(item)
                continue
            if item["kind"] == "card":
                need = words(item["spoken"]) / WPS + 0.8
                secs = max(item["seconds"], round(need))
                rows.append(f"card\t{item['name']}\t{secs}\t{item['line1']}\t{item['line2']}\t{item['spoken']}")
                continue
            acts = [dict(a) for a in item["actions"]]
            est = sum((web_seconds if take["kind"] == "web" else term_seconds)(a) for a in acts)
            hold = max(2.0, words(item["spoken"]) / WPS + 1.0 - est)
            if take["kind"] == "web":
                acts[0]["beat"] = item["name"]
                steps += acts + [pause(round(hold, 1))]
            else:
                steps += [{"beat": item["name"]}] + acts + [{"pause": round(hold, 1)}]
            rows.append(f"beat\t{item['name']}\t\t{item['line1']}\t{item['line2']}\t{item['spoken']}")
        if take["kind"] == "web":
            email, pw = PEOPLE[take["user"]]
            plan = {
                "baseURL": BASE, "viewport": {"width": 1440, "height": 810}, "slowMo": 220,
                "setup": [goto("/login"), {"do": "fill", "target": "input[type=email]", "value": email},
                          {"do": "fill", "target": "input[type=password]", "value": pw},
                          click("button[type=submit]"), wait_for("role=button[name=\"Account menu\"]")],
                "steps": steps,
            }
            json.dump(plan, open(os.path.join(d, "steps.json"), "w"), indent=1)
        else:
            scene = {
                "title": "meridian-mutual: tyk-ai-studio-workshop",
                "env": {"PROVIDER": "http://localhost:8720", "EXPENSE_CARD_KEY": "sk-personal-key-on-an-expense-card"},
                "steps": steps,
            }
            json.dump(scene, open(os.path.join(d, "scene.json"), "w"), indent=1)
        open(os.path.join(d, "story.tsv"), "w").write("\n".join(rows) + "\n")
        for name in ("prep", "after"):
            if take.get(name):
                open(os.path.join(d, name + ".sh"), "w").write(take[name] + "\n")
    total = sum(words(i["spoken"]) for t in TAKES for i in t["story"] if "spoken" in i)
    print(f"{len(TAKES)} takes written to {OUT}; {total} spoken words (about {total / WPS / 60:.1f} minutes of narration)")


if __name__ == "__main__":
    main()
