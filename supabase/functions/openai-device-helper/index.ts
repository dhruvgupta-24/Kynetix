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
    const errorHtml = `<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"><title>Error</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#13131F;color:#fff;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
display:flex;align-items:center;justify-content:center;min-height:100vh;padding:24px;text-align:center;}
.card{background:#1E1E2C;border:1px solid #2E2E3E;border-radius:20px;padding:32px 24px;max-width:380px;width:100%;}
h2{font-size:18px;font-weight:800;margin-bottom:10px;}
p{color:#9CA3AF;font-size:14px;}
</style>
</head><body>
<div class="card"><h2>⚠️ Invalid Request</h2><p>Missing session token. Please return to Kynetix and try again.</p></div>
</body></html>`;
    return new Response(errorHtml, { status: 400, headers: { 'Content-Type': 'text/html; charset=utf-8' } });
  }

  const saveUrl = `${apiBase}/functions/v1/openai-link-save`;

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Kynetix — OpenAI Connection</title>
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
      border-radius: 24px;
      padding: 36px 28px;
      max-width: 400px;
      width: 100%;
      text-align: center;
    }

    .icon { font-size: 40px; margin-bottom: 16px; }

    h1 {
      font-size: 20px;
      font-weight: 800;
      margin-bottom: 8px;
      color: #ffffff;
    }

    .subtitle {
      color: #9CA3AF;
      font-size: 14px;
      line-height: 1.5;
      margin-bottom: 28px;
    }

    .spinner {
      width: 36px;
      height: 36px;
      border: 3px solid #2E2E3E;
      border-top-color: #52B788;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
      margin: 0 auto 20px;
    }

    @keyframes spin { to { transform: rotate(360deg); } }

    #status-text {
      font-size: 13px;
      color: #6B7280;
      min-height: 20px;
      margin-bottom: 20px;
    }

    #return-btn {
      display: none;
      background: #52B788;
      color: #ffffff;
      border: none;
      border-radius: 14px;
      padding: 14px 24px;
      font-size: 15px;
      font-weight: 700;
      cursor: pointer;
      width: 100%;
      margin-top: 8px;
    }

    #return-btn:active { opacity: 0.85; }

    #success-icon {
      display: none;
      font-size: 36px;
      margin-bottom: 12px;
    }

    .error-box {
      display: none;
      background: rgba(255, 107, 53, 0.1);
      border: 1px solid rgba(255, 107, 53, 0.35);
      border-radius: 12px;
      padding: 14px;
      margin-top: 16px;
      color: #FF8A65;
      font-size: 13px;
      line-height: 1.5;
      text-align: left;
      word-break: break-word;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon" id="main-icon">🔗</div>
    <div id="success-icon">✅</div>
    <h1 id="main-title">Connecting to OpenAI</h1>
    <p class="subtitle" id="main-sub">Setting up your device login. This takes just a moment.</p>

    <div class="spinner" id="spinner"></div>
    <div id="status-text">Requesting device code...</div>
    <button id="return-btn" onclick="doReturn()">Return to Kynetix</button>
    <div class="error-box" id="error-box"></div>
  </div>

  <script>
    (function () {
      var NONCE = ${JSON.stringify(nonce)};
      var SAVE_URL = ${JSON.stringify(saveUrl)};
      var CLIENT_ID = ${JSON.stringify(CLIENT_ID)};
      var SCOPE = ${JSON.stringify(SCOPE)};

      var deepLink = '';

      function setStatus(msg) {
        document.getElementById('status-text').textContent = msg;
      }

      function showSuccess(link) {
        document.getElementById('spinner').style.display = 'none';
        document.getElementById('main-icon').style.display = 'none';
        document.getElementById('success-icon').style.display = 'block';
        document.getElementById('main-title').textContent = 'All set!';
        document.getElementById('main-sub').textContent = 'Returning you to Kynetix now...';
        setStatus('If the app did not open automatically, tap the button below.');
        document.getElementById('return-btn').style.display = 'block';
        document.getElementById('return-btn').setAttribute('data-href', link);
      }

      function showError(msg) {
        document.getElementById('spinner').style.display = 'none';
        var box = document.getElementById('error-box');
        box.style.display = 'block';
        box.textContent = msg;
        setStatus('Something went wrong. Please close this tab and try again in the app.');
      }

      function doReturn() {
        var btn = document.getElementById('return-btn');
        var link = btn.getAttribute('data-href') || deepLink;
        if (link) { window.location.href = link; }
      }

      async function run() {
        try {
          // Step 1: Fetch device code from OpenAI in browser (no 403 here)
          setStatus('Requesting device code from OpenAI...');

          var deviceRes = await fetch('https://auth.openai.com/oauth/device/code', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: 'client_id=' + encodeURIComponent(CLIENT_ID)
              + '&scope=' + encodeURIComponent(SCOPE)
          });

          if (!deviceRes.ok) {
            var errText = await deviceRes.text();
            showError('OpenAI returned an error (' + deviceRes.status + '). Details: ' + errText);
            return;
          }

          var data = await deviceRes.json();
          var deviceCode = data.device_code || data.device_auth_id;
          var userCode = data.user_code;
          var verificationUri = data.verification_uri || data.verification_url || 'https://chatgpt.com/auth/device';
          var interval = data.interval || data.interval_seconds || 5;
          var expiresIn = data.expires_in || 1800;
          var expiresAt = data.expires_at
            || new Date(Date.now() + expiresIn * 1000).toISOString();

          if (!deviceCode || !userCode) {
            showError('Unexpected response from OpenAI. Please try again.');
            return;
          }

          // Step 2: Save device session to backend using nonce — no JWT exposed here
          setStatus('Saving your session...');

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
            showError('Could not save your session. Please try again. (' + saveErr + ')');
            return;
          }

          // Step 3: Deep-link back to app with only non-sensitive display fields
          deepLink = 'kynetix://openai-auth/callback'
            + '?user_code=' + encodeURIComponent(userCode)
            + '&verification_uri=' + encodeURIComponent(verificationUri)
            + '&interval=' + interval;

          showSuccess(deepLink);

          // Attempt auto-redirect — Android browsers may block this without user gesture
          // so we always show the fallback button too
          setTimeout(function () {
            window.location.href = deepLink;
          }, 300);

        } catch (e) {
          showError((e && e.message) ? e.message : String(e));
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
