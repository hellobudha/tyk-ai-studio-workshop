// Meridian Mutual "Policy & Claims" API: the fictional insurer's internal system of record.
//
// It exists so the workshop has a real internal API to govern as an AI tool.
// It is NOT part of Tyk AI Studio. Note what it returns: customer names, dates of
// birth and bank details. That is exactly the data a governed AI platform has to
// keep away from the wrong model.
//
//   GET /policies/{policy_id}     e.g. POL-20418
//   GET /claims/{claim_id}        e.g. CLM-77120
//   GET /openapi.json             the spec AI Studio imports
//   GET /_calls?last=5            what the API was actually asked (lab evidence)
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = Number(process.env.PORT || 8080);
const API_KEY = process.env.MERIDIAN_API_KEY || '';
const calls = [];

const POLICIES = {
  'POL-20418': {
    policy_id: 'POL-20418', product: 'Home Buildings & Contents', holder: 'Amara Osei',
    date_of_birth: '1987-03-14', status: 'In force', cover_limit: '£450,000', excess: '£350',
    renewal_date: '2027-02-01', bank_account: 'GB29 NWBK 6016 1331 9268 19',
    notes: 'Customer prefers contact by email.',
  },
  'POL-31877': {
    policy_id: 'POL-31877', product: 'Motor Comprehensive', holder: 'Lukas Brandt',
    date_of_birth: '1979-11-02', status: 'In force', cover_limit: 'Market value', excess: '€500',
    renewal_date: '2027-06-15', bank_account: 'DE89 3704 0044 0532 0130 00',
    notes: 'Policy administered by the Frankfurt office.',
  },
  'POL-10993': {
    policy_id: 'POL-10993', product: 'Landlord Buildings', holder: 'Priscilla Hart',
    date_of_birth: '1965-07-23', status: 'Lapsed', cover_limit: '£900,000', excess: '£500',
    renewal_date: '2026-09-30', bank_account: 'GB94 BARC 1020 1530 0934 59',
    notes: 'Renewal reminder sent twice, no reply.',
  },
};

const CLAIMS = {
  'CLM-77120': {
    claim_id: 'CLM-77120', policy_id: 'POL-20418', type: 'Escape of water', status: 'Awaiting contractor report',
    reserve: '£4,500', handler: 'Tom Reyes', opened: '2026-11-09',
    next_action: 'Chase drying contractor for the moisture report',
  },
  'CLM-80455': {
    claim_id: 'CLM-80455', policy_id: 'POL-31877', type: 'Motor collision', status: 'Liability under review',
    reserve: '€7,200', handler: 'Sofia Keller', opened: '2026-11-17',
    next_action: 'Request third-party insurer details',
  },
};

function send(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
}

const spec = fs.readFileSync(path.join(__dirname, 'openapi.json'), 'utf8');

http.createServer((req, res) => {
  const url = new URL(req.url, 'http://meridian');
  const p = url.pathname.replace(/\/+$/, '');

  if (p === '/openapi.json') { res.writeHead(200, { 'Content-Type': 'application/json' }); return res.end(spec); }
  if (p === '/health' || p === '') return send(res, 200, { status: 'ok' });
  if (p === '/_calls') return send(res, 200, calls.slice(-Number(url.searchParams.get('last') || 10)));

  const authed = !API_KEY || req.headers['x-api-key'] === API_KEY;
  const seen = req.headers['x-api-key'] || req.headers['authorization'] || '';
  calls.push({
    at: new Date().toISOString(), method: req.method, path: p, authorised: authed,
    // A fingerprint only: enough to see which credential arrived, never the whole key.
    api_key_seen: seen ? String(seen).slice(0, 8) + '...' : '(none)',
  });
  if (calls.length > 200) calls.shift();
  if (!authed) return send(res, 401, { error: 'missing or invalid X-API-Key' });

  let m = p.match(/^\/policies\/([^/]+)$/);
  if (m && req.method === 'GET') {
    const row = POLICIES[decodeURIComponent(m[1]).toUpperCase()];
    return row ? send(res, 200, row) : send(res, 404, { error: 'policy not found' });
  }
  m = p.match(/^\/claims\/([^/]+)$/);
  if (m && req.method === 'GET') {
    const row = CLAIMS[decodeURIComponent(m[1]).toUpperCase()];
    return row ? send(res, 200, row) : send(res, 404, { error: 'claim not found' });
  }
  return send(res, 404, { error: 'not found' });
}).listen(PORT, () => console.log(`meridian-api listening on :${PORT}`));
