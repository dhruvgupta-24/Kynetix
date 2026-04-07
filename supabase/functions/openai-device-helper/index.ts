Deno.serve((req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204 });
  }

  const url = new URL(req.url);
  const nonce = url.searchParams.get('nonce');
  const api = url.searchParams.get('api') ?? 'https://sjrcqvqhycxtwwbivizy.supabase.co';

  if (!nonce || !api) {
    return new Response('Missing nonce or api parameter.', {
      status: 400,
      headers: { 'Content-Type': 'text/plain' },
    });
  }

  const redirectUrl =
    `https://sjrcqvqhycxtwwbivizy.supabase.co/storage/v1/object/public/public-pages/openai-helper.html` +
    `?nonce=${encodeURIComponent(nonce)}&api=${encodeURIComponent(api)}`;

  console.log(`[openai-device-helper] 302 redirect -> ${redirectUrl}`);

  return new Response(null, {
    status: 302,
    headers: { 'Location': redirectUrl },
  });
});
