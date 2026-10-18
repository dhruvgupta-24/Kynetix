# Sign in with ChatGPT: approval request draft

**Where to apply:** https://openai.com/form/sign-in-with-chatgpt-interest/

OpenAI offers this to "a select group of commercial partners" through a waitlist. Submit the form yourself as the app owner; it asks for your company and contact details. The answers below are a draft. Edit anything in `[brackets]`.

---

**Company / developer:** [Your legal name or company]
**Contact email:** [your email]
**App name:** Kynetix
**Platforms:** Android (Flutter); iOS planned
**Stage:** [Pre-launch / beta with N users]
**Expected weekly users:** [e.g. "fewer than 1,000"; pick the band that's true]

**What does your app do?**
Kynetix is a fitness and nutrition coach for Indian gym-goers. Users log meals (roti, dal, paneer…) and workouts. Kyno, the in-app AI coach, answers questions about their own training and nutrition history and estimates macros from meal text and photos.

**How will you use Sign in with ChatGPT?**
Plan usage only. The user's own ChatGPT plan powers Kyno, so ChatGPT subscribers bring their own AI and we don't need to resell model access. ChatGPT is an optional step during onboarding and in Settings. Users who don't connect get our default model.

**Integration details**
- OAuth 2.0 authorization code with PKCE (S256). The redirect is a loopback listener on `http://127.0.0.1:1455/auth/callback`, with `state` and `nonce` validated.
- Scopes: `openid profile email offline_access resource.invoke chatgpt.tokens.use.direct`, with `resource=https://api.openai.com/v1`.
- Inference goes through the public Responses API (`/v1/responses`, `stream: true`, `store: false`) and never through `backend-api`.
- Tokens are stored server-side only, in Supabase with service-role access. The device keeps only the issued `client_id`. Tokens are never logged. Users can disconnect at any time, which deletes the tokens.
- UI follows your guidelines:
  - the button reads "Continue with ChatGPT" and uses the official logo;
  - the first time, the user sees "You're using your ChatGPT plan" with a "Got it" button;
  - while the plan is in use, a "Using ChatGPT plan" chip appears with a "Manage usage" link to chatgpt.com/settings/usage;
  - usage-limit errors offer "Manage usage" as the primary action.

**Data shared with OpenAI**
Only what's needed to answer the user's question: their message, the relevant meal and workout context from their own logs, and optional meal photos. No data from other users is ever sent. We don't use ChatGPT data for anything except answering that user.

**Privacy policy URL:** [publish the privacy policy, then add the URL here]
**App or website URL:** [link]
