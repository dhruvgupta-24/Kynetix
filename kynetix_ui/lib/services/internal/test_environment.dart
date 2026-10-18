// Detects whether the code is running under `flutter test`.
//
// Used only to pick scheduling defaults (e.g. run deferred side effects
// immediately in tests so they stay deterministic). It never changes what is
// computed or persisted.
export 'test_environment_stub.dart'
    if (dart.library.io) 'test_environment_io.dart';
