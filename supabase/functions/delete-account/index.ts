// delete-account — permanently deletes the CALLER's account and data.
//
// Request:  POST, Authorization: Bearer <user JWT>, body { "confirm": "DELETE" }
// Response: 200 { deleted: true, ...counts } | 400 confirm_required | 401 | 500
//
// - The user id comes only from the verified JWT (never from the body).
// - Deletes only that user's rows (plan.ts), clears their attribution on
//   shared rows, then deletes the auth user with the admin API.
// - Idempotent: re-running after a partial failure finishes the job; rows
//   already gone count as 0, a missing auth user counts as deleted.
// - Logs counts only.
// - A Sign in with ChatGPT link is revoked at OpenAI first (best effort; see
//   shared/siwc.ts). Deletion goes ahead whether or not that succeeds.
//
// verify_jwt = false (like the other functions): the JWT is verified here
// with auth.getUser(), which supports the project's ES256 tokens.

// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  ATTRIBUTION_COLUMNS,
  CONFIRM_PHRASE,
  isConfirmed,
  isMissingTable,
  isUserNotFound,
  USER_TABLES,
} from "./plan.ts";
import { BodyTooLargeError, readJsonLimited } from "../shared/body_limit.ts";
import { revokeSiwcLink } from "../shared/siwc.ts";

declare const Deno: any;

/** The body is just { confirm: "DELETE" }. */
const MAX_BODY_BYTES = 64 * 1024;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

/** Removes every object under `prefix/` in one bucket, sub-folders included
 *  (folders come back from list() with a null id). Best effort: failures are
 *  logged and the account deletion continues. Returns how many were removed. */
async function purgeFolder(bucket: any, prefix: string, label: string, depth = 0): Promise<number> {
  let removed = 0;
  for (let round = 0; round < 20; round++) {
    const { data, error } = await bucket.list(prefix, { limit: 100 });
    if (error) {
      console.error(`[delete-account] ${label} list failed (continuing)`);
      return removed;
    }
    const entries: any[] = data ?? [];
    const files = entries.filter((e) => e.id != null).map((e) => `${prefix}/${e.name}`);
    const folders = entries.filter((e) => e.id == null).map((e) => `${prefix}/${e.name}`);
    if (depth < 3) {
      for (const f of folders) removed += await purgeFolder(bucket, f, label, depth + 1);
    }
    if (files.length === 0) return removed;
    const { error: rmErr } = await bucket.remove(files);
    if (rmErr) {
      console.error(`[delete-account] ${label} remove failed (continuing)`);
      return removed;
    }
    removed += files.length;
  }
  return removed;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Missing Authorization header' }, 401);
    const jwt = authHeader.replace('Bearer ', '').trim();

    const supabaseAnon = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: `Bearer ${jwt}` } } },
    );
    const { data: { user }, error: userErr } = await supabaseAnon.auth.getUser();
    if (userErr || !user?.id) {
      // A retry after a completed delete: the token is still well-formed but
      // its user is gone. Nothing to do (and nothing is touched).
      if (userErr && (isUserNotFound(userErr as any) || /does not exist/i.test((userErr as any).message ?? ''))) {
        return json({ deleted: true });
      }
      return json({ error: 'Unauthorized' }, 401);
    }
    const userId: string = user.id;

    let body: unknown;
    try {
      body = await readJsonLimited(req, null, MAX_BODY_BYTES);
    } catch (e) {
      if (e instanceof BodyTooLargeError) return json({ error: 'payload_too_large' }, 413);
      throw e;
    }
    if (!isConfirmed(body)) {
      return json({
        error: 'confirm_required',
        message: `Send { "confirm": "${CONFIRM_PHRASE}" } to delete this account.`,
      }, 400);
    }

    const admin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { persistSession: false, autoRefreshToken: false } },
    );

    // Revoke a ChatGPT (Sign in with ChatGPT) link at OpenAI before its row is
    // deleted. Best effort: failures are logged (no token) and ignored.
    {
      const { data: link, error: linkErr } = await admin
        .from('user_openai_links')
        .select('auth_method, refresh_token, oauth_client_id')
        .eq('user_id', userId)
        .maybeSingle();
      const outcome = linkErr ? 'failed' : await revokeSiwcLink(link);
      if (outcome !== 'skipped') console.log(`[delete-account] chatgpt revoke=${outcome}`);
    }

    const counts: Record<string, number> = {};

    for (const { table, column } of USER_TABLES) {
      const { error, count } = await admin
        .from(table)
        .delete({ count: 'exact' })
        .eq(column, userId);
      if (error) {
        if (isMissingTable(error)) { counts[table] = 0; continue; }
        console.error(`[delete-account] delete failed table=${table} code=${error.code ?? '-'}`);
        return json({ error: 'delete_failed', message: 'Could not delete your account. Try again.' }, 500);
      }
      counts[table] = count ?? 0;
    }

    for (const { table, column } of ATTRIBUTION_COLUMNS) {
      const { error, count } = await admin
        .from(table)
        .update({ [column]: null }, { count: 'exact' })
        .eq(column, userId);
      if (error) {
        if (isMissingTable(error)) continue;
        console.error(`[delete-account] unlink failed table=${table} code=${error.code ?? '-'}`);
        return json({ error: 'delete_failed', message: 'Could not delete your account. Try again.' }, 500);
      }
      counts[`${table}.${column}_cleared`] = count ?? 0;
    }

    // Storage: everything under the user's folder in every user bucket,
    // nested paths included (profile picture, feedback photos).
    for (const [bucketId, key] of [['avatars', 'avatar_files_removed'], ['feedback-photos', 'feedback_photos_removed']] as const) {
      counts[key] = await purgeFolder(admin.storage.from(bucketId), userId, bucketId);
    }

    const { error: delErr } = await admin.auth.admin.deleteUser(userId);
    if (delErr && !isUserNotFound(delErr)) {
      console.error(`[delete-account] auth delete failed status=${(delErr as any).status ?? '-'}`);
      return json({ error: 'delete_failed', message: 'Could not delete your account. Try again.' }, 500);
    }

    console.log(`[delete-account] done ${JSON.stringify(counts)}`);
    return json({ deleted: true });
  } catch (err: any) {
    console.error(`[delete-account] exception ${err?.name ?? 'Error'}`);
    return json({ error: 'delete_failed', message: 'Could not delete your account. Try again.' }, 500);
  }
});
