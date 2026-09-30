// Local HTTP Storage contract test. Fixtures are created and removed through
// Storage API only; local keys are captured in memory and never printed.
import { spawnSync } from 'node:child_process';
import { createHmac, randomUUID } from 'node:crypto';

const command = process.platform === 'win32' ? 'cmd.exe' : 'npx';
const args = process.platform === 'win32'
  ? ['/d', '/s', '/c', 'npx --no-install supabase status -o json']
  : ['--no-install', 'supabase', 'status', '-o', 'json'];
const statusResult = spawnSync(command, args, { encoding: 'utf8', timeout: 30_000 });
if (statusResult.status !== 0) throw new Error('Local Supabase status unavailable');
const local = JSON.parse(statusResult.stdout);
if (!/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(local.API_URL))
  throw new Error('Storage test requires a local API URL');

const tokenPart = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const payload = `${tokenPart({ alg: 'HS256', typ: 'JWT' })}.${tokenPart({
  aud: 'authenticated', role: 'authenticated',
  sub: '7a000000-0000-4000-8000-000000000001', iat: now, exp: now + 300,
})}`;
const authenticated = `${payload}.${createHmac('sha256', local.JWT_SECRET)
  .update(payload).digest('base64url')}`;
const fixture = `${randomUUID()}/${randomUUID()}.pdf`;
const url = `${local.API_URL}/storage/v1/object/certificates/${fixture}`;
const listUrl = `${local.API_URL}/storage/v1/object/list/certificates`;
const pdf = Buffer.from('%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\n%%EOF\n');

async function request(method, target, token, body, extra = {}) {
  return fetch(target, { method, headers: {
    apikey: local.ANON_KEY, Authorization: `Bearer ${token}`, ...extra,
  }, body });
}
function expectDenied(result, label) {
  if (result.ok) throw new Error(`${label}: unexpectedly allowed (${result.status})`);
  console.log(`PASS ${label}: HTTP ${result.status}`);
}

let created = false;
try {
  const authProbe = await request('GET', `${local.API_URL}/rest/v1/certificates?select=id&limit=0`,
    authenticated);
  if (!authProbe.ok) throw new Error(`Synthetic authenticated JWT was not accepted: HTTP ${authProbe.status}`);
  console.log('PASS authenticated JWT accepted by local Data API');
  let result = await request('POST', url, local.SERVICE_ROLE_KEY, pdf,
    { 'Content-Type': 'application/pdf', 'x-upsert': 'false' });
  if (!result.ok) throw new Error(`Local fixture upload failed: HTTP ${result.status}`);
  created = true;
  result = await request('POST', url, local.SERVICE_ROLE_KEY, pdf,
    { 'Content-Type': 'application/pdf', 'x-upsert': 'false' });
  expectDenied(result, 'Final path cannot be uploaded twice with upsert off');

  for (const [role, token] of [['anon', local.ANON_KEY], ['authenticated', authenticated]]) {
    expectDenied(await request('GET', url, token), `${role} download`);
    result = await request('POST', listUrl, token, JSON.stringify({ prefix: '' }),
      { 'Content-Type': 'application/json' });
    if (!result.ok || (await result.json()).length !== 0)
      throw new Error(`${role} list revealed objects or failed unexpectedly`);
    console.log(`PASS ${role} list: empty`);
    expectDenied(await request('POST', `${url}-new`, token, pdf,
      { 'Content-Type': 'application/pdf', 'x-upsert': 'false' }), `${role} upload`);
    expectDenied(await request('POST', url, token, pdf,
      { 'Content-Type': 'application/pdf', 'x-upsert': 'true' }), `${role} upsert`);
    expectDenied(await request('PUT', url, token, pdf,
      { 'Content-Type': 'application/pdf', 'x-upsert': 'true' }), `${role} replace`);
    result = await request('DELETE', `${local.API_URL}/storage/v1/object/certificates`, token,
      JSON.stringify({ prefixes: [fixture] }), { 'Content-Type': 'application/json' });
    if (result.ok) {
      const body = await result.json();
      if (Array.isArray(body) && body.length) throw new Error(`${role} deleted fixture`);
    }
    console.log(`PASS ${role} delete: fixture retained`);
  }

  let body = await (await request('GET', url, local.SERVICE_ROLE_KEY)).arrayBuffer();
  if (!Buffer.from(body).equals(pdf)) throw new Error('Client attempt changed stored fixture');
  console.log('PASS object bytes retained');
  expectDenied(await request('POST', `${url}-text`, local.SERVICE_ROLE_KEY,
    Buffer.from('text'), { 'Content-Type': 'text/plain', 'x-upsert': 'false' }),
  'Bucket rejects non-PDF MIME');
  expectDenied(await request('POST', `${url}-large`, local.SERVICE_ROLE_KEY,
    Buffer.alloc(8_388_609), { 'Content-Type': 'application/pdf', 'x-upsert': 'false' }),
  'Bucket rejects 8 MiB plus one byte');
} finally {
  if (created) {
    const result = await request('DELETE', `${local.API_URL}/storage/v1/object/certificates`,
      local.SERVICE_ROLE_KEY, JSON.stringify({ prefixes: [fixture] }),
      { 'Content-Type': 'application/json' });
    if (!result.ok) throw new Error(`Storage fixture cleanup failed: HTTP ${result.status}`);
  }
}
