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
  const token = url.searchParams.get('token');
  const apiBase = url.searchParams.get('api');

  if (!token || !apiBase) {
    return new Response('<html><body><h2>Error: Missing required parameters.</h2></body></html>', {
      status: 400,
      headers: { 'Content-Type': 'text/html' },
    });
  }

  const saveUrl = `${apiBase}/functions/v1/openai-link-save`;

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Kynetix — Connecting OpenAI</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: #13131F;
      color: #fff;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
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
      padding: 32px 28px;
      max-width: 420px;
      width: 100%;
      text-align: center;
    }
    h1 { font-size: 22px; font-weight: 800; margin-bottom: 8px; }
    p { color: #9CA3AF; font-size: 14px; line-height: 1.5; margin-bottom: 24px; }
    .spinner {
      width: 40px; height: 40px;
      border: 3px solid #2E2E3E;
      border-top-color: #52B788;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
      margin: 0 auto 24px;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
    .status { font-size: 13px; color: #6B7280; margin-top: 16px; }
    .error { color: #FF6B35; font-size: 14px; margin-top: 16px; }
  </style>
</head>
<body>
  <div class="card">
    <div class="spinner" id="spinner"></div>
    <h1>Connecting to OpenAI</h1>
    <p>Please wait while we initiate the device login flow...</p>
    <div class="status" id="status">Requesting device code from OpenAI...</div>
    <div class="error" id="error" style="display:none"></div>
  </div>

  <script>
    const TOKEN = ${JSON.stringify(token)};
    const SAVE_URL = ${JSON.stringify(saveUrl)};
    const CLIENT_ID = ${JSON.stringify(CLIENT_ID)};
    const SCOPE = ${JSON.stringify(SCOPE)};

    function setStatus(msg) {
      document.getElementById('status').textContent = msg;
    }

    function showError(msg) {
      document.getElementById('spinner').style.display = 'none';
      const el = document.getElementById('error');
      el.style.display = 'block';
      el.textContent = 'Error: ' + msg;
    }

    async function run() {
      try {
        // Step 1: Fetch device code from OpenAI IN BROWSER (no 403 here)
        setStatus('Requesting device code from OpenAI...');
        const deviceRes = await fetch('https://auth.openai.com/oauth/device/code', {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({ client_id: CLIENT_ID, scope: SCOPE })
        });

        if (!deviceRes.ok) {
          const errText = await deviceRes.text();
          showError('OpenAI returned ' + deviceRes.status + ': ' + errText);
          return;
        }

        const data = await deviceRes.json();
        const deviceCode = data.device_code ?? data.device_auth_id;
        const userCode = data.user_code;
        const verificationUri = data.verification_uri ?? data.verification_url ?? 'https://chatgpt.com/auth/device';
        const interval = data.interval ?? data.interval_seconds ?? 5;
        const expiresIn = data.expires_in ?? 1800;
        const expiresAt = data.expires_at ?? new Date(Date.now() + expiresIn * 1000).toISOString();

        if (!deviceCode || !userCode) {
          showError('OpenAI returned unexpected response shape: ' + JSON.stringify(data));
          return;
        }

        // Step 2: Save device_code to Supabase (secure, server-stored)
        setStatus('Saving session...');
        const saveRes = await fetch(SAVE_URL, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + TOKEN,
          },
          body: JSON.stringify({
            device_code: deviceCode,
            user_code: userCode,
            verification_url: verificationUri,
            interval_seconds: interval,
            expires_at: expiresAt,
          })
        });

        if (!saveRes.ok) {
          const errJson = await saveRes.text();
          showError('Failed to save session: ' + errJson);
          return;
        }

        // Step 3: Deep-link back to Flutter app with non-sensitive fields only
        setStatus('Returning to Kynetix...');
        const deepLink = 'kynetix://openai-auth/callback'
          + '?user_code=' + encodeURIComponent(userCode)
          + '&verification_uri=' + encodeURIComponent(verificationUri)
          + '&interval=' + interval;

        window.location.href = deepLink;

      } catch (e) {
        showError(e.message || String(e));
      }
    }

    run();
  </script>
</body>
</html>`;

  return new Response(html, {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      ...corsHeaders,
    },
  });
});
