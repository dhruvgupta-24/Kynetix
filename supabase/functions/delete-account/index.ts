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

declare const Deno: any;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

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

    const body = await req.json().catch(() => null);
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
