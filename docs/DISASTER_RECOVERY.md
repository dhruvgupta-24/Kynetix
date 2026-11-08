# Kynetix disaster recovery

What to do when something breaks badly. Keep this short and current.

## What protects what

| Asset | Where it lives | Backup | Restore |
|---|---|---|---|
| Database rows (profiles, meals, workouts, auth users) | Supabase `sjrcqvqhycxtwwbivizy` (Seoul) | `tools/ops/backup_db.py`, daily 21:00 via Task Scheduler ("Kynetix DB backup"), 14 kept in `Documents/Kynetix-private/backups/` | `tools/ops/restore_db.py` (below) |
| Database schema, RLS, functions | `supabase/migrations/` in git | GitHub (and every clone) | `supabase db push` |
| Edge functions | `supabase/functions/` in git | GitHub | `supabase functions deploy <name>` |
| Edge function secrets (AI keys, router secret, SMTP) | Supabase dashboard > Edge Functions > Secrets | **None. Keep a copy in a password manager.** | Re-enter them |
| Storage files (avatars, feedback photos) | Supabase Storage | Not backed up (only the file list is) | Users re-upload avatars; feedback photos are lost |
| Android upload key | `kynetix_ui/android/key.properties` + keystore file | **Keep a second copy off this PC** (USB / password manager) | Play App Signing: Play Console > Setup > App signing > "Request upload key reset" if lost |
| Website | `site/` in git, GitHub Pages | GitHub | Push again |

**Supabase free plan keeps no backups at all** (`supabase backups list` returns none). The local daily backup is the only copy. Copy the newest file off this PC every week or so (USB drive or a private cloud folder). The files contain every user's data and password hashes: never put them in the repo (it is public) or share them.

Targets: lose at most 1 day of data (RPO 24 h); back online within about 2 hours (RTO).

## Check that backups work (monthly, 2 minutes)

```
python tools/ops/backup_db.py                # takes a backup now, prints row counts
type %USERPROFILE%\Documents\Kynetix-private\backups\last-run.log
type %USERPROFILE%\Documents\Kynetix-private\backups\health.log
```

`health.log` is the daily health report (crashes, new users, AI budget, unread safety reports). "NEEDS A LOOK" means open the app's inbox or the Supabase logs.

## Scenario 1: bad migration or wrong data written (project still alive)

1. Stop the bleeding: revert the commit on `main` and push (auto-deploy re-applies functions; a migration that dropped data does not come back by itself).
2. Make the restore file, only for the damaged tables:
   ```
   python tools/ops/restore_db.py <newest backup>.json.gz restore.sql --only public.day_logs,public.profiles
   ```
3. Read `restore.sql` headers, then run it: `supabase db query --linked --project-ref sjrcqvqhycxtwwbivizy -f restore.sql`.
   Inserts only, `on conflict do nothing`: rows that still exist are left alone, missing ones come back.
4. Delete `restore.sql` (it holds user data).

## Scenario 2: Supabase project gone (deleted, region outage, account lost)

1. Create a new Supabase project. Note the new ref and anon key.
2. `supabase link --project-ref <new>` then `supabase db push` (all migrations) and deploy every function: `supabase functions deploy` for each folder in `supabase/functions` (not `shared`).
3. Re-enter the edge function secrets from your password manager. Recreate Auth settings: Google provider (web client ID and secret), redirect URLs (`kynetix://login-callback`, `kynetix://reset-password`), SMTP.
4. Full restore: `python tools/ops/restore_db.py <newest>.json.gz restore.sql`, then `supabase db query --linked -f restore.sql`. Users keep their logins (auth.users and identities come back with password hashes).
5. Point the app and site at the new project: `lib/config/supabase_secrets.dart` (url, anonKey), `site/parent/index.html` (function URL and its CSP `connect-src`), `tools/ops/*.py` (`PROJECT_REF`). Ship an app update.
6. Delete `restore.sql`.

## Scenario 3: a key leaked

- **Anon key**: public by design; RLS protects data. Nothing to do.
- **Service role key / DB password**: Supabase dashboard > Settings > API > roll the key (and Database > reset password). Update function secrets if any use it. Check `auth.users` and recent rows for anything odd.
- **AI provider keys**: revoke at the provider, set the new value in function secrets. The global AI budget (`ai_global_usage`) caps the damage meanwhile.
- **Upload keystore**: request an upload key reset in Play Console. Play App Signing means users are not affected.

## Scenario 4: AI providers down or out of credit

The router falls through Gemini > Groq > OpenRouter free. If all fail, users see "Kyno is busy". Logging, workouts and history keep working offline. To switch AI off cleanly, set the `system_flags` row that disables AI (see `20261106120000_hardening.sql`).

## Scenario 5: this PC dies

Everything except the backups and the upload key is on GitHub. That is why the backups and the keystore need a second copy elsewhere. On a new PC: clone the repo, `supabase login`, copy `key.properties` + keystore + `lib/config/*secrets.dart` back from your safe copy, re-create the scheduled task (see `tools/ops/backup_db.py` header).

## Load and security re-test

`python tools/ops/stress_test.py` runs live security probes (RLS, storage paths, function auth, body limits, AI rate limit) and a capped 2-minute load test. It signs up a throwaway account; when Supabase asks for email confirmation it falls back to read-only mode. Results from 8 Nov 2026: all probes pass; 86 req/s sustained with 0 errors, p50 about 290 ms, p95 about 1.3 s; a 14-request AI burst let exactly 10 through and answered the rest with 429.
