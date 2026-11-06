// Legacy Codex device-code linking (openai-link-start -> poll -> verify).
//
// That flow signs in through the Codex CLI's public client id and device
// page, which a third-party app should not offer. New links go through Sign
// in with ChatGPT (openai-link-siwc). openai-link-start refuses to start a
// new device-code link unless ALLOW_LEGACY_DEVICE_LINK=true. Accounts already
// linked that way keep working: ai-chat-router, token refresh, status,
// verify and disconnect are unchanged, and a session started before the
// switch can still finish through openai-link-poll (sessions expire in 15 min).

export type EnvGet = (name: string) => string | undefined;

export const LEGACY_DEVICE_LINK_ENV = 'ALLOW_LEGACY_DEVICE_LINK';

/** Pure: true only when the env flag is exactly "true" (case-insensitive). */
export function legacyDeviceLinkAllowed(env: EnvGet): boolean {
  return (env(LEGACY_DEVICE_LINK_ENV) ?? '').trim().toLowerCase() === 'true';
}

/** Body for the 410 a client gets when the device-code flow is retired. */
export const LEGACY_DEVICE_LINK_GONE = {
  error: 'device_link_retired',
  message: 'Linking with a code is no longer available. Update Kynetix and use Continue with ChatGPT instead.',
} as const;
