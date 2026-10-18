import 'dart:async';

/// Upper bounds for network calls, so a dead connection fails (and falls back
/// or retries) instead of hanging a spinner or a sync run forever. A timed-out
/// call throws [TimeoutException], which every caller already treats like any
/// other network error. Writes guarded by these are idempotent upserts or
/// deletes, so one that lands after its timeout is harmless.
class NetTimeouts {
  NetTimeouts._();

  /// Cloud sync / profile reads and writes (Supabase tables).
  static const sync = Duration(seconds: 20);

  /// Short edge-function calls (ChatGPT link start / poll / status).
  static const edge = Duration(seconds: 30);

  /// One complete AI answer (meal estimate, coach reply, weekly summary).
  static const ai = Duration(seconds: 90);

  /// A streamed AI reply: only until the response starts, never the stream.
  static const aiFirstByte = Duration(seconds: 60);

  /// Account deletion removes every row the user has.
  static const accountDeletion = Duration(seconds: 45);
}

extension NetTimeoutFuture<T> on Future<T> {
  /// [timeout] that throws a [TimeoutException] naming [what].
  Future<T> within(Duration limit, String what) => timeout(
        limit,
        onTimeout: () =>
            throw TimeoutException('$what timed out', limit),
      );
}
