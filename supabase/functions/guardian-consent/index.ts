// guardian-consent: a parent's OK for a teen account (13 to 17).
//
// verify_jwt is off at the gateway because the parent opens a web page and
// has no Kynetix account. Each action checks its own credential:
//   request / status  the teen's Supabase JWT (checked with auth.getUser)
//   view / decide / revoke  the 256-bit link token (only its SHA-256 is stored)
//
// Flow: the app calls `request` and shares the returned link (WhatsApp or any
// app). The parent's page calls `view`, then `decide` (approve or decline).
// The same link later lets the parent `revoke`, which locks the teen's app.

// @ts-ignore
import { createClient } from 'npm:@supabase/supabase-js@2';
import {
  effectiveStatus,
  GuardianError,
  isTokenShape,
  LINK_DAYS,
  newToken,
  parentLink,
  parseDate,
  ageOn,
  sha256Hex,
  validateDecision,
  validateRequest,
} from '../shared/guardian.ts';
import { BodyTooLargeError, readJsonLimited } from '../shared/body_limit.ts';

declare const Deno: any;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
}

function admin() {
  return createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
}

async function teenUser(req: Request): Promise<{ id: string }> {
  const auth = req.headers.get('Authorization') ?? '';
  const jwt = auth.replace(/^Bearer\s+/i, '').trim();
  if (!jwt) throw new GuardianError(401, 'unauthorized', 'Sign in again.');
  const anon = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_ANON_KEY') ?? '', {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const { data, error } = await anon.auth.getUser();
  if (error || !data?.user) throw new GuardianError(401, 'unauthorized', 'Sign in again.');
  return { id: data.user.id };
}

function teenView(row: any) {
  return {
    status: effectiveStatus(row),
    parent_name: row?.status === 'approved' ? row.parent_name : null,
    relation: row?.status === 'approved' ? row.relation : null,
    expires_at: row?.expires_at ?? null,
    decided_at: row?.decided_at ?? null,
  };
}

const COLS = 'user_id, child_dob, child_first_name, status, parent_name, relation, requested_at, expires_at, decided_at';

async function rowByToken(db: any, token: unknown) {
  if (!isTokenShape(token)) throw new GuardianError(404, 'not_found', 'This link is not valid any more.');
  const { data, error } = await db.from('guardian_consents').select(COLS).eq('token_hash', await sha256Hex(token)).maybeSingle();
  if (error) throw new GuardianError(503, 'busy', 'Could not load this right now. Try again in a minute.');
  if (!data) throw new GuardianError(404, 'not_found', 'This link is not valid any more. Ask for a new one.');
  return data;
}

async function handle(req: Request, body: any): Promise<Response> {
  const db = admin();
  const action = body?.action;

  if (action === 'request') {
    const user = await teenUser(req);
    const { dob, firstName } = validateRequest(body);
    const { data: existing } = await db.from('guardian_consents').select(COLS).eq('user_id', user.id).maybeSingle();
    if (existing?.status === 'approved' && ageOn(parseDate(existing.child_dob)!) < 18) {
      return json({ ...teenView(existing), link: null });
    }
    // A parent's "no" (or a later revoke) is final: a fresh request must not
    // reset it to pending with a new link the teen could answer themselves.
    if (existing?.status === 'declined' || existing?.status === 'revoked') {
      throw new GuardianError(
        409,
        'parent_said_no',
        'A parent or guardian already said no. If they change their mind, they can email kynetix.app@gmail.com.',
      );
    }
    const token = newToken();
    const row = {
      user_id: user.id,
      // Fixed at the first request: editing the birthday later changes nothing here.
      child_dob: existing?.child_dob ?? dob,
      child_first_name: firstName,
      token_hash: await sha256Hex(token),
      status: 'pending',
      parent_name: null,
      parent_birth_year: null,
      relation: null,
      requested_at: new Date().toISOString(),
      expires_at: new Date(Date.now() + LINK_DAYS * 86400_000).toISOString(),
      decided_at: null,
    };
    const { error } = await db.from('guardian_consents').upsert(row, { onConflict: 'user_id' });
    if (error) throw new GuardianError(503, 'busy', 'Could not make a link right now. Try again in a minute.');
    console.log(`[guardian] request user=${user.id}`);
    return json({ ...teenView(row), link: parentLink(token) });
  }

  if (action === 'status') {
    const user = await teenUser(req);
    const { data, error } = await db.from('guardian_consents').select(COLS).eq('user_id', user.id).maybeSingle();
    if (error) throw new GuardianError(503, 'busy', 'Could not check right now.');
    return json(teenView(data));
  }

  if (action === 'view') {
    const row = await rowByToken(db, body?.token);
    return json({
      child_first_name: row.child_first_name,
      child_age: ageOn(parseDate(row.child_dob)!),
      status: effectiveStatus(row),
      parent_name: row.status === 'approved' ? row.parent_name : null,
      decided_at: row.decided_at,
    });
  }

  if (action === 'decide') {
    const row = await rowByToken(db, body?.token);
    const status = effectiveStatus(row);
    if (status === 'expired') throw new GuardianError(410, 'expired', 'This link timed out. Ask your teen to send a new one.');
    if (status !== 'pending') throw new GuardianError(409, 'already_decided', 'This request has already been answered.');
    const d = validateDecision(body, row.child_dob);
    const update = d.decision === 'approve'
      ? { status: 'approved', parent_name: d.parentName, parent_birth_year: d.parentBirthYear, relation: d.relation, decided_at: new Date().toISOString() }
      : { status: 'declined', decided_at: new Date().toISOString() };
    // Only a still-pending row changes, so two taps cannot both win.
    const { data, error } = await db.from('guardian_consents').update(update)
      .eq('user_id', row.user_id).eq('status', 'pending').select('status').maybeSingle();
    if (error) throw new GuardianError(503, 'busy', 'Could not save that. Try again in a minute.');
    if (!data) throw new GuardianError(409, 'already_decided', 'This request has already been answered.');
    console.log(`[guardian] ${data.status} user=${row.user_id}`);
    return json({ status: data.status });
  }

  if (action === 'revoke') {
    const row = await rowByToken(db, body?.token);
    if (row.status !== 'approved') throw new GuardianError(409, 'not_approved', 'There is nothing to switch off.');
    const { error } = await db.from('guardian_consents')
      .update({ status: 'revoked', decided_at: new Date().toISOString() })
      .eq('user_id', row.user_id).eq('status', 'approved');
    if (error) throw new GuardianError(503, 'busy', 'Could not save that. Try again in a minute.');
    console.log(`[guardian] revoked user=${row.user_id}`);
    return json({ status: 'revoked' });
  }

  throw new GuardianError(400, 'unknown_action', 'Unknown action.');
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  try {
    let body: any;
    try {
      body = await readJsonLimited(req, null, 8 * 1024);
    } catch (e) {
      if (e instanceof BodyTooLargeError) return json({ error: 'payload_too_large' }, 413);
      return json({ error: 'bad_json', message: 'Bad request.' }, 400);
    }
    return await handle(req, body);
  } catch (e) {
    if (e instanceof GuardianError) return json({ error: e.code, message: e.message }, e.status);
    console.error('[guardian] unexpected', e instanceof Error ? e.message : String(e));
    return json({ error: 'internal', message: 'Something went wrong. Try again in a minute.' }, 500);
  }
});

