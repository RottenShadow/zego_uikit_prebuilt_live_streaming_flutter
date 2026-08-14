// Dart imports:
import 'dart:async';

/// Serializes the ZegoUIKit singleton lifecycle across stream-screen
/// replacements.
///
/// When a live-stream page is replaced (e.g. push-replacing `/stream/A` with
/// `/stream/B`), the outgoing page's `dispose` can run before or after the
/// replacement page's `initState`. Both touch the same global engine and the
/// same singleton managers, so a naive fire-and-forget teardown/setup can
/// interleave: a stale `leaveRoom` kills the new session's room, and a stale
/// teardown nulls the managers the new session just created.
///
/// The queue ([run]) executes lifecycle tasks in FIFO order and the chain
/// waits for each task's full completion, so the previous session's teardown
/// always settles before the next session's setup starts. Because the enqueue
/// order of init vs teardown is not guaranteed across a route replacement,
/// ownership ([init]/[dispose]/[adopt]) lets a teardown that lost the race to
/// a newer session become a no-op instead of destroying it.
abstract final class ZegoLiveStreamingLifecycle {
  static int _counter = 0;
  static int? _owner;
  static Future<void> _queue = Future.value();

  /// Claims a fresh session token for a live-stream page.
  static int claim() => ++_counter;

  /// Runs [task] after every previously queued lifecycle task has settled.
  static Future<T> run<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    // Swallow errors from the chain link so a failed task never wedges the
    // queue; the caller still sees its own error via [result].
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Enqueues this session's setup and marks [token] as the current owner.
  ///
  /// Runs behind any teardown that was already queued, and takes ownership
  /// before [task] so a teardown enqueued later by the replaced session sees
  /// the newer owner and becomes a no-op.
  static Future<T> init<T>(int token, Future<T> Function() task) {
    return run(() async {
      _owner = token;
      return task();
    });
  }

  /// Enqueues this session's teardown, running [task] only while [token]
  /// still owns the SDK. A stale teardown is a no-op, so a replaced session
  /// can never tear down the replacement.
  static Future<void> dispose(int token, Future<void> Function() task) {
    return run(() async {
      if (_owner != token) {
        return;
      }

      try {
        await task();
      } finally {
        if (_owner == token) {
          _owner = null;
        }
      }
    });
  }

  /// Re-claims ownership for a session restoring from minimized mode.
  ///
  /// The minimized session kept its room and managers alive (its dispose was
  /// a no-op), so ownership just moves to the fresh State's token.
  static Future<void> adopt(int token) {
    return run(() async {
      _owner = token;
    });
  }

  /// Whether [token] currently owns the global SDK.
  static bool owns(int token) => _owner == token;
}
