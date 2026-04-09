// ─── AppSecrets (EXAMPLE TEMPLATE) ───────────────────────────────────────────
//
// Copy this file to secrets.dart (which is .gitignored).
// secrets.dart is NOT committed. NEVER put real keys here.
//
// AI provider keys (OpenAI, OpenRouter) are backend-only Supabase secrets.
// Set them with:
//   npx supabase secrets set OPENAI_API_KEY=sk-... OPENROUTER_API_KEY=sk-or-...
//
// Flutter does not need any AI provider keys at all.

class AppSecrets {
  // No private keys required in Flutter.
  // AI routing is fully handled server-side by Supabase Edge Functions.
}
