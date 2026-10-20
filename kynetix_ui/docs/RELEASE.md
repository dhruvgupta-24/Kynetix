# Releasing Kynetix

## 1. Back up the upload key first
`android/upload-keystore.jks` and `android/key.properties` (which holds its password) were generated on this machine on 2026-10-16. Both are git-ignored, so they exist only here.

- **Copy both files to a password manager or another safe place now.** If you lose them, Play App Signing can reset the upload key, but that takes a support request and days.
- Never commit them, and never share them.

## 2. Two kinds of release build

| Purpose | Command | Signed with |
|---|---|---|
| Test on your phone (fast, keeps data) | `flutter run --release -d <device>` | debug key, same as your existing install |
| Upload to Play | see below | upload key |

Store build. Obfuscation keeps your Dart code hard to reverse; keep the symbols folder for reading crash stack traces.

```powershell
$env:ORG_GRADLE_PROJECT_kynetixStoreRelease="true"
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
Remove-Item Env:ORG_GRADLE_PROJECT_kynetixStoreRelease
```

Upload `build/app/outputs/bundle/release/app-release.aab`.

**Warning:** don't install a store-signed build over a debug-signed one on your phone. Android refuses, and "fixing" that by uninstalling erases all the meal data stored locally on the phone.

Bump `version:` in `pubspec.yaml` (e.g. `1.0.1+2`) before each upload.

## 3. Play Console checklist
- **Account deletion:**
  - In-app: Settings → Delete account.
  - Web: the public page is https://dhruvgupta-24.github.io/Kynetix/delete-account/ (from `site/delete-account/`); paste that URL into the Data safety form's "Delete account URL".
- **Privacy policy URL:** publish `docs/PRIVACY_POLICY.md` as a web page after filling in the `[placeholders]`.
- **Health Connect:** fill in the Health apps declaration (steps, weight, sleep, HRV, all read-only, to set calorie targets).
- **Data safety:** draft answers are below. Check them against your final setup.
- **Target audience:** 18+.

## 4. Data safety: draft answers

| Data type | Collected | Shared | Purpose | Optional |
|---|---|---|---|---|
| Name, email, phone (sign-in) | Yes | No | Account management | No (one of email/phone/Google) |
| Health & fitness (meals, workouts, steps, weight, sleep, HRV) | Yes | Yes, with AI processors (OpenRouter / OpenAI) to answer the user's own questions | App functionality, personalisation | Health Connect is optional |
| Photos (meal photos) | Yes, only when the user attaches them | Yes, with the AI processor for estimation | App functionality | Yes |
| App info & performance (crash logs) | Yes (in-house, no PII) | No | Analytics / diagnostics | No |

- **Encrypted in transit:** yes.
- **Users can request deletion:** yes, in-app and on the web.
- **Data used for advertising:** no.
