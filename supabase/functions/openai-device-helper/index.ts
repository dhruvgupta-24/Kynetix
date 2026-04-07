import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const CLIENT_ID = 'app_EMoamEEZ73f0CkXaXp7hrann';
const SCOPE = 'openid profile email offline_access api.connectors.read api.connectors.invoke';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const url = new URL(req.url);
  const nonce = url.searchParams.get('nonce');
  const apiBase = url.searchParams.get('api') ?? 'https://sjrcqvqhycxtwwbivizy.supabase.co';

  if (!nonce) {
    const errorHtml = `<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>Error</title>
<style>body{background:#13131F;color:#FF6B35;font-family:sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;text-align:center;padding:24px;}</style>
</head><body><h2>Invalid Request</h2><p>Missing session identifier. Please return to the app and try again.</p></body></html>`;
    return new Response(errorHtml, { status: 400, headers: { 'Content-Type': 'text/html; charset=utf-8' } });
  }

  const saveUrl = `${apiBase}/functions/v1/openai-link-save`;

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Kynetix — Connecting OpenAI</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: #13131F;
      color: #ffffff;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 24px;
    }
    .card {
      background: #1E1E2C;
      border: 1px solid #2E2E3E;
      border-radius: 20px;
      padding: 36px 28px;
      max-width: 400px;
      width: 100%;
      text-align: center;
    }
    .logo { font-size: 32px; margin-bottom: 16px; }
    h1 { font-size: 20px; font-weight: 800; margin-bottom: 8px; }
    p { color: #9CA3AF; font-size: 14px; line-height: 1.5; }
    .spinner {
      width: 36px; height: 36px;
      border: 3px solid #2E2E3E;
      border-top-color: #52B788;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
      margin: 20px auto;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
    #status { color: #6B7280; font-size: 13px; margin-top: 12px; }
    #error-box {
      display: none;
      background: rgba(255,107,53,0.1);
      border: 1px solid rgba(255,107,53,0.4);
      border-radius: 12px;
      padding: 14px;
      margin-top: 16px;
      color: #FF6B35;
      font-size: 13px;
      word-break: break-all;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">🔗</div>
    <h1>Connecting to OpenAI</h1>
    <p>Please wait while we set up your device login.</p>
    <div class="spinner" id="spinner"></div>
    <div id="status">Requesting device code...</div>
    <div id="error-box"></div>
  </div>

  <script>
    (function () {
      var NONCE = ${JSON.stringify(nonce)};
      var SAVE_URL = ${JSON.stringify(saveUrl)};
      var CLIENT_ID = ${JSON.stringify(CLIENT_ID)};
      var SCOPE = ${JSON.stringify(SCOPE)};

      function setStatus(msg) {
        document.getElementById('status').textContent = msg;
      }

      function showError(msg) {
        document.getElementById('spinner').style.display = 'none';
        var box = document.getElementById('error-box');
        box.style.display = 'block';
        box.textContent = msg;
      }

      async function run() {
        try {
          setStatus('Requesting device code from OpenAI...');

          var deviceRes = await fetch('https://auth.openai.com/oauth/device/code', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: 'client_id=' + encodeURIComponent(CLIENT_ID) + '&scope=' + encodeURIComponent(SCOPE)
          });

          if (!deviceRes.ok) {
            var errText = await deviceRes.text();
            showError('OpenAI error ' + deviceRes.status + ': ' + errText);
            return;
          }

          var data = await deviceRes.json();
          var deviceCode = data.device_code || data.device_auth_id;
          var userCode = data.user_code;
          var verificationUri = data.verification_uri || data.verification_url || 'https://chatgpt.com/auth/device';
          var interval = data.interval || data.interval_seconds || 5;
          var expiresIn = data.expires_in || 1800;
          var expiresAt = data.expires_at || new Date(Date.now() + expiresIn * 1000).toISOString();

          if (!deviceCode || !userCode) {
            showError('Unexpected OpenAI response: ' + JSON.stringify(data));
            return;
          }

          setStatus('Saving session...');

          var saveRes = await fetch(SAVE_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              nonce: NONCE,
              device_code: deviceCode,
              user_code: userCode,
              verification_url: verificationUri,
              interval_seconds: interval,
              expires_at: expiresAt
            })
          });

          if (!saveRes.ok) {
            var saveErr = await saveRes.text();
            showError('Save failed: ' + saveErr);
            return;
          }

          setStatus('Returning to Kynetix...');

          var deepLink = 'kynetix://openai-auth/callback'
            + '?user_code=' + encodeURIComponent(userCode)
            + '&verification_uri=' + encodeURIComponent(verificationUri)
            + '&interval=' + interval;

          window.location.href = deepLink;

        } catch (e) {
          showError(e && e.message ? e.message : String(e));
        }
      }

      run();
    })();
  </script>
</body>
</html>`;

  return new Response(html, {
    status: 200,
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
  });
});
