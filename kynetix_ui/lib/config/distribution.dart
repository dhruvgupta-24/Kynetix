// ─── Distribution ─────────────────────────────────────────────────────────────
// Which channel this build ships through, fixed at compile time.
//
// Play builds (the default) must never update themselves outside Google Play,
// so the sideload updater exists only when the build is made with
//
//   flutter build apk --release --split-per-abi --dart-define=KYNETIX_SIDELOAD=true
//
// Even then, UpdateCheckService stays off if Google Play installed the app.

/// True for the APK offered on the website (GitHub Releases). False for Play.
const bool kSideload = bool.fromEnvironment('KYNETIX_SIDELOAD');
