# The demo: one week at Meridian Mutual in nine minutes

A narrated walkthrough of the whole story, recorded against the live workshop stack. Use the video as it
is, or present the same sequence live with the script below.

- **Video:** [video/tyk-ai-studio-workshop-demo.mp4](video/tyk-ai-studio-workshop-demo.mp4)
  (1280x720, about 12 MB), recorded on 24 November 2026.
- **Length:** 8 minutes 45 seconds, sixteen takes.
- **What is real:** every screen is Tyk AI Studio Enterprise 2.2.2 running in the workshop stack, and every
  terminal command is executed while it is recorded. Nothing is mocked up or edited in.
- **What is simulated:** the three model providers, as everywhere in this workshop. The opening card says so.
- **Narration:** a synthetic voice (macOS text to speech). The words are in
  [video/storyboard.py](video/storyboard.py).

## The sequence

Each row is one take. *Shown* is what is on screen. *Said* is the point the narration makes.

| # | Day | Shown | Said |
|---|---|---|---|
| 1 | Mon 08:40 | Terminal. Tom's prompt goes straight to a provider, then `./workshop sim seen openai` | The provider received a date of birth, National Insurance number, email and bank account. Nobody can say who sent it or what it cost. |
| 2 | Mon | Console as Priya: LLM providers, Secrets, an App's credential | One front door. Providers registered once with a privacy level, keys held as secrets, software identified by an App. |
| 3 | Mon | Terminal. Three `./workshop ask` calls, then the provider's view | One URL and one key reach three providers. The provider only sees Meridian's contract key. |
| 4 | Tue | AI Portal as Dana: Browse, then Create New App | Dana sees only what her team was given, and asks for an app in her own words. |
| 5 | Tue | Console as Priya: the request, then **Approve this App** | One click. No ticket, and no provider key changed hands. |
| 6 | Wed | Console as Priya: Filters, then the filters attached to OpenAI | Built-in guardrails plus one rule of Meridian's own, attached to the provider so every app is covered. |
| 7 | Wed | Terminal. Monday's prompt again, the provider's view, then an SIU prompt | The provider now receives placeholders. A fraud case file is blocked with a reason. |
| 8 | Wed | Console: Compliance overview, Filter events | Every detection is an event: what was found and what was done, never the data. |
| 9 | Wed night | Terminal. `./workshop runaway` | A looping job is stopped by its one dollar budget. |
| 10 | Wed night | Console: Analytics, Application Costs and Team Costs | Every dollar has an app, an owner and a team. |
| 11 | Thu | AI Portal as Dana: an app with OpenAI and the Policy and Claims tool | AI Studio refuses to pair customer data with a public model. Monday's privacy levels prevented a mistake. |
| 12 | Thu | Chat as Tom: a handbook question, then a policy lookup | Answers from Meridian's handbook and its policy system, with bank details withheld by a filter on the tool. |
| 13 | Thu | Terminal. `./workshop mcp` | An AI agent gets the same tool over MCP, with the same permissions and the same filter. |
| 14 | Fri am | Console: Edge Gateways | Two edge gateways, London and Frankfurt, configured from one place. |
| 15 | Fri am | Terminal. Harbour EU at each edge, an OpenAI outage, then `meridian/fast` | The private model exists in Frankfurt only. An outage fails over unnoticed. Apps ask for a capability, not a vendor. |
| 16 | Fri pm | Console as Marcus: Audit trail, one change expanded | A read-only auditor sees who changed what, field by field, including his own refused attempt. |

## Presenting it live

Follow the same order. The off-camera preparation between takes is just the act scripts:

```bash
./workshop reset && ./workshop up
```

| Before take | Run |
|---|---|
| 2 | `./workshop act 1` |
| 4 | `./workshop act 2 --setup-only` (teams and catalogs, without Dana's request) |
| 6 | `./workshop act 2` then `./workshop act 3` |
| 9 | `./workshop act 4 --setup-only` (budgets, without running the job) |
| 11 | `./workshop act 5` |
| 14 | `./workshop act 6` |
| 16 | `./workshop act 7` |

Keep two things open: the console at <http://localhost:8700> and a terminal in this folder with a large
font. Sign-in details are in `./workshop who`. Use a private browser window for Dana, Tom and Marcus so you
do not have to sign Priya out.

If you have fifteen minutes instead of ten, stop after take 7 and let the room read the provider's view of
the redacted prompt. It is the moment the demo is built around.

## Recording it again

The recorder resets the workshop, replays the week, records every take while the product does the thing,
adds title cards, subtitles and narration, and joins the takes into `video/out/`. Copy the result over
`video/tyk-ai-studio-workshop-demo.mp4` when you are happy with it.

```bash
(cd video && npm install)
```

```bash
EVIDENCE_VIDEO_HOME=<path to the evidence-video toolkit> video/record.sh
```

- [video/storyboard.py](video/storyboard.py) is the single source for the video: every take, every on-screen
  action, every subtitle and every spoken line. Change the story there.
- [video/termcast.py](video/termcast.py) records the terminal takes. It runs each command for real and draws
  the actual output. A command that fails, or whose output is missing a phrase the take depends on, fails
  the take.
- The browser takes are replayed in Chromium by Playwright. Signing in happens off camera, and passwords are
  read from `.env`, never written into a steps file.
- Title cards, subtitles, the voiceover and the per-take checks come from Tyk's internal `evidence-video`
  toolkit (`make_video.py` and `record-web.mjs`). It is not part of this repository. Point
  `EVIDENCE_VIDEO_HOME` at a checkout of it.

To re-record a single take without resetting, name it:

```bash
ONLY="07-guardrails-proof" NO_RESET=1 EVIDENCE_VIDEO_HOME=<path> video/record.sh
```

Takes depend on the state earlier takes leave behind, so a full run is the reliable one.
