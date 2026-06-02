// Shared OAuth token refresh helper for Deno Edge Functions
// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2";

const CODEX_CLIENT_ID = 'app_EMoamEEZ73f0CkXaXp7hrann';
const OPENAI_TOKEN_URL = 'https://auth.openai.com/oauth/token';

export async function refreshAccessTokenIfNeeded(
  supabaseAdmin: any,
  userId: string,
  link: {
    access_token: string | null;
    refresh_token: string | null;
    expires_at: string | null;
    is_connected: boolean;
  }
): Promise<{ accessToken: string; expiresAt: string } | null> {
  if (!link.is_connected || !link.access_token) {
    return null;
  }

  // Check if token is expired or expiring in less than 5 minutes (300,000 ms)
  const expiresAtMs = link.expires_at ? new Date(link.expires_at).getTime() : 0;
  const isExpiring = expiresAtMs === 0 || (expiresAtMs - Date.now() < 5 * 60 * 1000);

  if (!isExpiring) {
    // Access token is still valid
    return {
      accessToken: link.access_token,
      expiresAt: link.expires_at || '',
    };
  }

  // Token is expired or expiring; attempt refresh
  if (!link.refresh_token) {
    console.warn(`[OAUTH REFRESH] user=${userId} token is expired but no refresh_token is present.`);
    // Mark as expired in DB
    await supabaseAdmin
      .from('user_openai_links')
      .update({
        fallback_reason: 'token_expired',
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', userId);
    return null;
  }

  console.log(`[OAUTH REFRESH] user=${userId} access token expired/expiring. Refreshing via OpenAI...`);

  try {
    const params = new URLSearchParams({
      grant_type: 'refresh_token',
      client_id: CODEX_CLIENT_ID,
      refresh_token: link.refresh_token,
    });

    const res = await fetch(OPENAI_TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params.toString(),
    });

    if (!res.ok) {
      const errBody = await res.text();
      console.error(`[OAUTH REFRESH] OpenAI refresh request failed status=${res.status} body=${errBody.slice(0, 200)}`);

      // Handle permanent authorization/token failures by disconnecting user
      if (res.status === 400 || res.status === 401 || res.status === 403) {
        console.warn(`[OAUTH REFRESH] Permanent error from OpenAI. Disconnecting user=${userId} credentials.`);
        await supabaseAdmin
          .from('user_openai_links')
          .update({
            is_connected: false,
            fallback_reason: 'refresh_failed',
            updated_at: new Date().toISOString(),
          })
          .eq('user_id', userId);
      }
      return null;
    }

    const data = await res.json();
    const newAccessToken = data.access_token;
    if (!newAccessToken) {
      console.error(`[OAUTH REFRESH] Refresh succeeded but returned no access_token. response=${JSON.stringify(data)}`);
      return null;
    }

    const newRefreshToken = data.refresh_token ?? link.refresh_token; // use old if not rotated
    const expiresSeconds = data.expires_in ? Number(data.expires_in) : 3600;
    const newExpiresAt = new Date(Date.now() + expiresSeconds * 1000).toISOString();

    console.log(`[OAUTH REFRESH] Refresh token flow success for user=${userId}. expires_in=${expiresSeconds}s`);

    // Update DB with new tokens
    const { error: updateErr } = await supabaseAdmin
      .from('user_openai_links')
      .update({
        access_token: newAccessToken,
        refresh_token: newRefreshToken,
        expires_at: newExpiresAt,
        last_refreshed_at: new Date().toISOString(),
        fallback_reason: null, // Clear any previous fallback reason
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', userId);

    if (updateErr) {
      console.error(`[OAUTH REFRESH] Failed to save refreshed tokens in DB: ${updateErr.message}`);
      // return new credentials anyway to complete the current request
    }

    return {
      accessToken: newAccessToken,
      expiresAt: newExpiresAt,
    };

  } catch (err: any) {
    console.error(`[OAUTH REFRESH] Unhandled exception during token refresh: ${err?.message ?? err}`);
    return null;
  }
}
