// Run: node probe_models.js
// This calls codex-model-probe with your Supabase session token and prints the full report.
//
// USAGE:
//   1. Open Kynetix app, open DevTools / log the JWT, or get it from the .env
//   2. Set SUPABASE_JWT below (the user's JWT, NOT the anon key)
//   3. node probe_models.js

const SUPABASE_URL  = 'https://sjrcqvqhycxtwwbivizy.supabase.co';
const FUNCTION_NAME = 'codex-model-probe';

// ─── FILL IN YOUR JWT HERE ───────────────────────────────────────────────────
// Get it from: Kynetix app → profile → copy session token
// Or from your test .env if you have a test account
const SUPABASE_JWT = process.env.SUPABASE_JWT || 'PASTE_YOUR_SUPABASE_USER_JWT_HERE';
// ─────────────────────────────────────────────────────────────────────────────

if (SUPABASE_JWT === 'PASTE_YOUR_SUPABASE_USER_JWT_HERE') {
  console.error('ERROR: Set SUPABASE_JWT env var or paste your JWT into probe_models.js');
  console.error('Usage: SUPABASE_JWT=eyJ... node probe_models.js');
  process.exit(1);
}

async function main() {
  console.log(`Calling ${FUNCTION_NAME}...`);
  const res = await fetch(`${SUPABASE_URL}/functions/v1/${FUNCTION_NAME}`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${SUPABASE_JWT}`,
      'Content-Type':  'application/json',
    },
  });

  const body = await res.text();
  console.log(`\nHTTP ${res.status}\n`);
  try {
    console.log(JSON.stringify(JSON.parse(body), null, 2));
  } catch {
    console.log(body);
  }
}

main().catch(console.error);
