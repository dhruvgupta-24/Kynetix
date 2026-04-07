const HTML_HEADERS: Record<string, string> = {
  "Content-Type": "text/html; charset=utf-8",
  "Cache-Control": "no-store, no-cache, must-revalidate, proxy-revalidate",
  "Pragma": "no-cache",
  "Expires": "0",
  "X-Content-Type-Options": "nosniff",
};

Deno.serve((_req: Request) => {
  console.log("[openai-device-helper] STATIC HTML TEST SERVED");

  const html =
`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>HTML Render Test</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: #13131F;
      color: #ffffff;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 24px;
    }
    .card {
      background: #1E1E2C;
      border: 1px solid #2E2E3E;
      border-radius: 24px;
      padding: 40px 28px;
      max-width: 380px;
      width: 100%;
      text-align: center;
    }
    .icon { font-size: 48px; margin-bottom: 20px; }
    h1 { font-size: 22px; font-weight: 800; margin-bottom: 12px; }
    p { color: #9CA3AF; font-size: 15px; line-height: 1.6; margin-bottom: 32px; }
    a.btn {
      display: block;
      background: #52B788;
      color: #ffffff;
      text-decoration: none;
      border-radius: 14px;
      padding: 16px 24px;
      font-size: 16px;
      font-weight: 700;
    }
    a.btn:active { opacity: 0.8; }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">&#x2705;</div>
    <h1>HTML Render Test</h1>
    <p>If you can see this as a designed page, HTML rendering works.</p>
    <a class="btn" href="kynetix://openai-auth/callback?test=1">Open Kynetix</a>
  </div>
</body>
</html>`;

  return new Response(html, { status: 200, headers: HTML_HEADERS });
});
