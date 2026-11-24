// LLM Simulator for the Tyk AI Studio workshop.
//
// One zero-dependency Node process that plays three LLM "providers" so the
// workshop runs offline, costs nothing, and behaves the same every time:
//
//   /openai/v1/...      OpenAI wire format      (public cloud provider)
//   /anthropic/v1/...   Anthropic Messages API  (public cloud provider)
//   /harbour/v1/...     OpenAI wire format      (Meridian's self-hosted EU model)
//
// It is NOT part of Tyk AI Studio. It stands in for the vendors that AI Studio
// governs. Everything interesting in the workshop happens in front of it.
//
// Extras that make the labs observable:
//   GET  /_sim/requests?provider=openai&last=5   what each provider really received
//   POST /_sim/outage   {"provider":"openai","on":true}   simulate a provider outage
//   POST /_sim/reset                                      clear the request log and outages
//   GET  /_sim/health
'use strict';

const http = require('http');
const crypto = require('crypto');

const PORT = Number(process.env.PORT || 8080);
const MAX_LOG = 200;

// provider -> behaviour
const PROVIDERS = {
  openai: {
    label: 'OpenAI (simulated)',
    wire: 'openai',
    models: ['gpt-5.5', 'gpt-5.5-mini', 'text-embedding-3-small'],
    defaultModel: 'gpt-5.5-mini',
    latencyMs: 220,
  },
  anthropic: {
    label: 'Anthropic (simulated)',
    wire: 'anthropic',
    models: ['claude-sonnet-5-5', 'claude-haiku-5-5'],
    defaultModel: 'claude-sonnet-5-5',
    latencyMs: 260,
  },
  harbour: {
    label: 'Harbour (simulated self-hosted, Frankfurt)',
    wire: 'openai',
    models: ['harbour-large', 'harbour-embed'],
    defaultModel: 'harbour-large',
    latencyMs: 120,
  },
};

const state = {
  log: [],          // newest last
  outage: {},       // provider -> true
  counters: {},     // provider -> n
};

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------
const tokens = (s) => Math.max(1, Math.ceil(String(s || '').length / 4));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const rid = (p) => p + crypto.randomBytes(12).toString('hex');

function send(res, status, body, headers = {}) {
  const data = typeof body === 'string' ? body : JSON.stringify(body);
  res.writeHead(status, { 'Content-Type': 'application/json', ...headers });
  res.end(data);
}

function readBody(req) {
  return new Promise((resolve) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8');
      try { resolve({ raw, json: raw ? JSON.parse(raw) : {} }); }
      catch { resolve({ raw, json: null }); }
    });
  });
}

// Flatten OpenAI / Anthropic message content (string or content-part array).
function textOf(content) {
  if (content == null) return '';
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content.map((p) => {
      if (typeof p === 'string') return p;
      if (p.type === 'text') return p.text || '';
      if (p.type === 'tool_result') return textOf(p.content);
      return '';
    }).join('\n');
  }
  return String(content);
}

function record(provider, req, path, body) {
  const auth = req.headers['authorization'] || req.headers['x-api-key'] || '';
  const entry = {
    at: new Date().toISOString(),
    provider,
    method: req.method,
    path,
    // Only a fingerprint of the vendor key: enough to prove which key arrived.
    vendor_key_seen: auth ? auth.replace(/^Bearer\s+/i, '').slice(0, 14) + '...' : '(none)',
    model: body && body.model,
    stream: !!(body && body.stream),
    messages: body && Array.isArray(body.messages)
      ? body.messages.map((m) => ({ role: m.role, content: textOf(m.content).slice(0, 12000) }))
      : undefined,
    system: body && body.system ? textOf(body.system).slice(0, 2000) : undefined,
    input: body && body.input !== undefined ? body.input : undefined,
    tools: body && Array.isArray(body.tools)
      ? body.tools.map((t) => (t.function ? t.function.name : t.name))
      : undefined,
  };
  state.log.push(entry);
  if (state.log.length > MAX_LOG) state.log.shift();
  state.counters[provider] = (state.counters[provider] || 0) + 1;
}

// ---------------------------------------------------------------------------
// the "model": small, deterministic, insurance-flavoured
// ---------------------------------------------------------------------------
const POLICY_RE = /\bPOL-\d{4,}\b/i;
const CLAIM_RE = /\bCLM-\d{4,}\b/i;

function lastOf(messages, role) {
  for (let i = messages.length - 1; i >= 0; i--) if (messages[i].role === role) return messages[i];
  return null;
}

function pickTool(tools, text) {
  if (!Array.isArray(tools) || !tools.length) return null;
  const named = tools.map((t) => ({
    name: t.function ? t.function.name : t.name,
    schema: t.function ? t.function.parameters : t.input_schema,
  }));
  const pol = text.match(POLICY_RE);
  const clm = text.match(CLAIM_RE);
  const find = (re) => named.find((t) => re.test(t.name || ''));
  if (clm) {
    const t = find(/claim/i);
    if (t) return { tool: t, args: argsFor(t.schema, { claim: clm[0].toUpperCase() }) };
  }
  if (pol) {
    const t = find(/polic/i);
    if (t) return { tool: t, args: argsFor(t.schema, { policy: pol[0].toUpperCase() }) };
  }
  return null;
}

// Fill whatever parameter the tool schema declares with the id we found.
function argsFor(schema, ids) {
  const out = {};
  const props = (schema && schema.properties) || {};
  const keys = Object.keys(props);
  const id = ids.claim || ids.policy;
  const want = ids.claim ? /claim/i : /polic/i;
  const key = keys.find((k) => want.test(k)) || keys.find((k) => /id|number|ref/i.test(k)) || keys[0];
  if (key) out[key] = id; else out[ids.claim ? 'claim_id' : 'policy_id'] = id;
  return out;
}

function summariseToolResult(raw) {
  let obj = null;
  try { obj = JSON.parse(raw); } catch { /* plain text result */ }
  if (obj && obj.policy_id) {
    return `Policy ${obj.policy_id} is a ${obj.product} policy held by ${obj.holder}. ` +
      `Status: ${obj.status}. Cover limit: ${obj.cover_limit}. Excess: ${obj.excess}. ` +
      `Renewal date: ${obj.renewal_date}. ` +
      (obj.notes ? `Note on file: ${obj.notes} ` : '') +
      (/withheld/i.test(String(obj.bank_account)) ? 'Bank details and date of birth were withheld from me by policy.' : '');
  }
  if (obj && obj.claim_id) {
    return `Claim ${obj.claim_id} (${obj.type}) is currently "${obj.status}". ` +
      `Reserve: ${obj.reserve}. Assigned handler: ${obj.handler}. ` +
      `Next action: ${obj.next_action}.`;
  }
  return 'Here is what the system returned: ' + String(raw).slice(0, 600);
}

// AI Studio's chat adds retrieved passages to the user's message like this:
//   [CONTEXT]\nContext for this message: \n<passages>\n\n[/CONTEXT]\n<question>
function splitContext(text) {
  const m = String(text).match(/\[CONTEXT\]([\s\S]*?)\[\/CONTEXT\]\s*([\s\S]*)$/);
  if (!m) return { context: '', question: String(text).trim() };
  return { context: m[1].replace(/^\s*Context for this message:\s*/i, ''), question: m[2].trim() };
}

const STOP = new Set(('a an and are as at be by can do does for from how i in is it of on or our that the their ' +
  'there this to was we what when where which who why will with you your claim claims').split(' '));
const words = (t) => (String(t).toLowerCase().match(/[a-z0-9£]+/g) || []).filter((w) => w.length > 2 && !STOP.has(w));

// "Reads" the retrieved passages: returns the sentences that share most words with the question.
function fromContext(context, question) {
  const qs = new Set(words(question));
  if (!qs.size) return null;
  const sentences = context
    .split(/\n+/).filter((l) => l.trim() && !/^#/.test(l.trim()))
    .join(' ').split(/(?<=[.!?])\s+/).map((x) => x.trim()).filter((x) => x.length > 20);
  const scored = sentences.map((text, i) => {
    const ws = new Set(words(text));
    let hits = 0; qs.forEach((w) => { if (ws.has(w)) hits += 1; });
    return { text, i, score: hits / Math.sqrt(ws.size || 1), hits };
  }).filter((x) => x.hits >= 2).sort((x, y) => y.score - x.score);
  if (!scored.length) return null;
  const top = scored.slice(0, 2).filter((x) => x.hits >= scored[0].hits - 1).sort((x, y) => x.i - y.i);
  return top.map((x) => x.text).join(' ');
}

function answer(provider, model, messages, system) {
  const user = lastOf(messages, 'user');
  const raw = textOf(user && user.content).trim();
  const tag = `[${model} via ${PROVIDERS[provider].label}]`;
  if (!raw) return `${tag} I did not receive a question.`;

  // AI Studio asks the model to name a new chat.
  const title = raw.match(/generate a short, descriptive title[\s\S]*User message:\s*([\s\S]+)$/i);
  if (title) {
    const t = title[1].replace(/[?.!]+$/, '').split(/\s+/).slice(0, 7).join(' ');
    return t.charAt(0).toUpperCase() + t.slice(1);
  }

  const { context, question: q } = splitContext(raw);
  const lower = q.toLowerCase();

  if (/^(hi|hello|hey)\b/.test(lower)) {
    return `Hello! I am the Meridian Mutual assistant running on ${model}. Ask me about a claim, a policy, or the claims handbook.`;
  }
  if (/(what|which) model|who are you/.test(lower)) {
    return `I am ${model}, served by ${PROVIDERS[provider].label}.`;
  }
  if (/summari[sz]e|summary/.test(lower) && /claim/.test(lower)) {
    return 'Claim summary:\n' +
      '- Incident: escape of water from a failed washing-machine hose, kitchen and hallway affected.\n' +
      '- Cover: buildings and contents, policy in force at the date of loss.\n' +
      '- Estimate: £4,850 (drying £900, flooring £2,700, redecoration £1,250).\n' +
      '- Excess: £350. Recommended reserve: £4,500.\n' +
      '- Next step: appoint drying contractor and request two flooring quotes.';
  }
  if (/draft|write|email|letter/.test(lower)) {
    return 'Dear customer,\n\nThank you for telling us about your claim. We have everything we need for the ' +
      'next step and a handler will contact you within two working days.\n\nKind regards,\nMeridian Mutual Claims';
  }
  if (/translate/.test(lower)) {
    return 'Sehr geehrte Kundin, sehr geehrter Kunde, wir haben Ihre Schadenmeldung erhalten und melden uns innerhalb von zwei Werktagen.';
  }
  if (context) {
    const found = fromContext(context, q);
    if (found) return `According to the claims handbook: ${found}`;
    return 'The claims handbook passages I was given do not cover that. Please check with your team lead.';
  }
  if (/fraud|suspicious|red flag/.test(lower)) {
    return 'Fraud triage (advisory only, a handler must decide):\n' +
      '1. Policy inception 11 days before the loss: elevated.\n' +
      '2. No police reference for a theft over £2,000: elevated.\n' +
      '3. Third claim in 14 months on the same address: review.\n' +
      'Suggested route: refer to the Special Investigations Unit before settlement.';
  }
  return `${tag} Simulated answer to: "${q.slice(0, 240)}"`;
}

// ---------------------------------------------------------------------------
// OpenAI wire format
// ---------------------------------------------------------------------------
async function openaiChat(provider, req, res, body) {
  const cfg = PROVIDERS[provider];
  const model = body.model || cfg.defaultModel;
  const messages = Array.isArray(body.messages) ? body.messages : [];
  const last = messages[messages.length - 1] || {};
  const promptTokens = tokens(messages.map((m) => textOf(m.content)).join('\n')) + messages.length * 3;

  let content = null;
  let toolCalls = null;

  if (last.role === 'tool') {
    content = summariseToolResult(textOf(last.content));
  } else {
    const picked = last.role === 'user' ? pickTool(body.tools, splitContext(textOf(last.content)).question) : null;
    if (picked) {
      toolCalls = [{
        id: rid('call_'),
        type: 'function',
        function: { name: picked.tool.name, arguments: JSON.stringify(picked.args) },
      }];
    } else {
      content = answer(provider, model, messages, '');
    }
  }

  const completionTokens = toolCalls ? 18 : tokens(content);
  const usage = {
    prompt_tokens: promptTokens,
    completion_tokens: completionTokens,
    total_tokens: promptTokens + completionTokens,
  };
  const id = rid('chatcmpl-');
  const created = Math.floor(Date.now() / 1000);
  await sleep(cfg.latencyMs);

  if (!body.stream) {
    return send(res, 200, {
      id, object: 'chat.completion', created, model,
      choices: [{
        index: 0,
        message: toolCalls
          ? { role: 'assistant', content: null, tool_calls: toolCalls }
          : { role: 'assistant', content },
        finish_reason: toolCalls ? 'tool_calls' : 'stop',
      }],
      usage,
    });
  }

  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
  });
  const chunk = (delta, finish = null, extra = {}) => res.write('data: ' + JSON.stringify({
    id, object: 'chat.completion.chunk', created, model,
    choices: [{ index: 0, delta, finish_reason: finish }],
    ...extra,
  }) + '\n\n');

  chunk({ role: 'assistant', content: toolCalls ? null : '' });
  if (toolCalls) {
    const tc = toolCalls[0];
    chunk({ tool_calls: [{ index: 0, id: tc.id, type: 'function', function: { name: tc.function.name, arguments: '' } }] });
    chunk({ tool_calls: [{ index: 0, function: { arguments: tc.function.arguments } }] });
    chunk({}, 'tool_calls');
  } else {
    const words = content.split(/(\s+)/);
    for (let i = 0; i < words.length; i += 3) {
      chunk({ content: words.slice(i, i + 3).join('') });
      await sleep(18);
    }
    chunk({}, 'stop');
  }
  // Usage chunk (sent whether or not stream_options.include_usage was set:
  // a gateway needs it to meter streaming calls).
  res.write('data: ' + JSON.stringify({
    id, object: 'chat.completion.chunk', created, model, choices: [], usage,
  }) + '\n\n');
  res.write('data: [DONE]\n\n');
  res.end();
}

// Deterministic bag-of-words embedding: texts that share words land close
// together, which is all retrieval needs for the workshop handbook.
function embed(text, dim) {
  const v = new Array(dim).fill(0);
  const words = String(text).toLowerCase().match(/[a-z0-9£]+/g) || [];
  for (const w of words) {
    if (w.length < 3) continue;
    const h = crypto.createHash('md5').update(w).digest();
    const idx = h.readUInt32BE(0) % dim;
    v[idx] += (h[4] & 1) ? 1 : -1;
  }
  const norm = Math.sqrt(v.reduce((a, b) => a + b * b, 0)) || 1;
  return v.map((x) => +(x / norm).toFixed(6));
}

function openaiEmbeddings(provider, res, body) {
  const inputs = Array.isArray(body.input) ? body.input : [body.input];
  const dim = Number(body.dimensions) || 1536;
  const total = inputs.reduce((a, t) => a + tokens(t), 0);
  return send(res, 200, {
    object: 'list',
    model: body.model || 'text-embedding-3-small',
    data: inputs.map((t, i) => ({ object: 'embedding', index: i, embedding: embed(t, dim) })),
    usage: { prompt_tokens: total, total_tokens: total },
  });
}

function openaiModels(provider, res) {
  return send(res, 200, {
    object: 'list',
    data: PROVIDERS[provider].models.map((id) => ({ id, object: 'model', created: 1750000000, owned_by: provider })),
  });
}

// ---------------------------------------------------------------------------
// Anthropic Messages wire format
// ---------------------------------------------------------------------------
async function anthropicMessages(provider, req, res, body) {
  const cfg = PROVIDERS[provider];
  const model = body.model || cfg.defaultModel;
  const messages = Array.isArray(body.messages) ? body.messages : [];
  const last = messages[messages.length - 1] || {};
  const lastParts = Array.isArray(last.content) ? last.content : [];
  const toolResult = lastParts.find((p) => p.type === 'tool_result');

  const inputTokens = tokens(textOf(body.system) + messages.map((m) => textOf(m.content)).join('\n')) + messages.length * 3;
  let text = null;
  let toolUse = null;

  if (toolResult) {
    text = summariseToolResult(textOf(toolResult.content));
  } else {
    const picked = last.role === 'user' ? pickTool(body.tools, splitContext(textOf(last.content)).question) : null;
    if (picked) toolUse = { type: 'tool_use', id: rid('toolu_'), name: picked.tool.name, input: picked.args };
    else text = answer(provider, model, messages, body.system);
  }
  const outputTokens = toolUse ? 18 : tokens(text);
  const id = rid('msg_');
  const usage = { input_tokens: inputTokens, output_tokens: outputTokens };
  const stopReason = toolUse ? 'tool_use' : 'end_turn';
  await sleep(cfg.latencyMs);

  if (!body.stream) {
    return send(res, 200, {
      id, type: 'message', role: 'assistant', model,
      content: toolUse ? [toolUse] : [{ type: 'text', text }],
      stop_reason: stopReason, stop_sequence: null, usage,
    });
  }

  res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive' });
  const ev = (type, data) => res.write(`event: ${type}\ndata: ${JSON.stringify({ type, ...data })}\n\n`);
  ev('message_start', {
    message: { id, type: 'message', role: 'assistant', model, content: [], stop_reason: null, stop_sequence: null,
      usage: { input_tokens: inputTokens, output_tokens: 1 } },
  });
  if (toolUse) {
    ev('content_block_start', { index: 0, content_block: { type: 'tool_use', id: toolUse.id, name: toolUse.name, input: {} } });
    ev('content_block_delta', { index: 0, delta: { type: 'input_json_delta', partial_json: JSON.stringify(toolUse.input) } });
  } else {
    ev('content_block_start', { index: 0, content_block: { type: 'text', text: '' } });
    const words = text.split(/(\s+)/);
    for (let i = 0; i < words.length; i += 3) {
      ev('content_block_delta', { index: 0, delta: { type: 'text_delta', text: words.slice(i, i + 3).join('') } });
      await sleep(18);
    }
  }
  ev('content_block_stop', { index: 0 });
  ev('message_delta', { delta: { stop_reason: stopReason, stop_sequence: null }, usage: { output_tokens: outputTokens } });
  ev('message_stop', {});
  res.end();
}

// ---------------------------------------------------------------------------
// router
// ---------------------------------------------------------------------------
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://sim');
  const path = url.pathname.replace(/\/+$/, '') || '/';

  if (path === '/_sim/health' || path === '/') {
    return send(res, 200, { status: 'ok', providers: Object.keys(PROVIDERS), outage: state.outage, counters: state.counters });
  }
  if (path === '/_sim/requests') {
    const provider = url.searchParams.get('provider');
    const last = Number(url.searchParams.get('last') || 10);
    let rows = state.log;
    if (provider) rows = rows.filter((r) => r.provider === provider);
    return send(res, 200, rows.slice(-last));
  }
  if (path === '/_sim/reset' && req.method === 'POST') {
    state.log = []; state.outage = {}; state.counters = {};
    return send(res, 200, { status: 'reset' });
  }
  if (path === '/_sim/outage' && req.method === 'POST') {
    const { json } = await readBody(req);
    if (!json || !PROVIDERS[json.provider]) return send(res, 400, { error: 'provider must be one of ' + Object.keys(PROVIDERS).join(', ') });
    if (json.on) state.outage[json.provider] = true; else delete state.outage[json.provider];
    return send(res, 200, { provider: json.provider, outage: !!json.on });
  }

  const m = path.match(/^\/(openai|anthropic|harbour)(\/.*)?$/);
  if (!m) return send(res, 404, { error: { message: 'unknown path ' + path, type: 'not_found' } });
  const provider = m[1];
  const rest = m[2] || '/';
  const { json: body } = await readBody(req);
  record(provider, req, rest, body || {});

  if (state.outage[provider]) {
    await sleep(80);
    return send(res, 503, { error: { message: `${PROVIDERS[provider].label} is unavailable (simulated outage)`, type: 'server_error', code: 'service_unavailable' } });
  }
  if (req.method !== 'GET' && body === null) {
    return send(res, 400, { error: { message: 'invalid JSON body', type: 'invalid_request_error' } });
  }

  try {
    if (/\/models$/.test(rest) && req.method === 'GET') return openaiModels(provider, res);
    if (/\/messages$/.test(rest)) return await anthropicMessages(provider, req, res, body);
    if (/\/chat\/completions$/.test(rest)) return await openaiChat(provider, req, res, body);
    if (/\/embeddings$/.test(rest)) return openaiEmbeddings(provider, res, body);
    return send(res, 404, { error: { message: `the simulator does not implement ${req.method} ${rest}`, type: 'not_found' } });
  } catch (e) {
    return send(res, 500, { error: { message: 'simulator error: ' + e.message, type: 'server_error' } });
  }
});

server.listen(PORT, () => console.log(`llm-sim listening on :${PORT} providers=${Object.keys(PROVIDERS).join(',')}`));
