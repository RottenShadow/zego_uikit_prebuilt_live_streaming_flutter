import 'package:flutter_test/flutter_test.dart';
import 'package:zego_uikit_prebuilt_live_streaming/src/internal/lifecycle.dart';

void main() {
  test('same session: setup then teardown in order', () async {
    final log = <String>[];
    final token = ZegoLiveStreamingLifecycle.claim();

    await ZegoLiveStreamingLifecycle.init(token, () async {
      log.add('init');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    expect(ZegoLiveStreamingLifecycle.owns(token), isTrue);

    await ZegoLiveStreamingLifecycle.dispose(token, () async {
      log.add('dispose');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });

    expect(log, ['init', 'dispose']);
    expect(ZegoLiveStreamingLifecycle.owns(token), isFalse);
  });

  test('replacement: new session init wins, stale teardown is a no-op', () async {
    final log = <String>[];
    final a = ZegoLiveStreamingLifecycle.claim();
    await ZegoLiveStreamingLifecycle.init(a, () async => log.add('initA'));

    final b = ZegoLiveStreamingLifecycle.claim();
    final initBFuture =
        ZegoLiveStreamingLifecycle.init(b, () async => log.add('initB'));
    final disposeAFuture = ZegoLiveStreamingLifecycle.dispose(a, () async {
      log.add('disposeA');
    });

    await initBFuture;
    await disposeAFuture;

    expect(log, ['initA', 'initB']);
    expect(ZegoLiveStreamingLifecycle.owns(b), isTrue);
  });

  test('old session torn down before new session init', () async {
    final log = <String>[];
    final a = ZegoLiveStreamingLifecycle.claim();
    await ZegoLiveStreamingLifecycle.init(a, () async => log.add('initA'));

    await ZegoLiveStreamingLifecycle.dispose(a, () async {
      log.add('disposeA');
    });

    final b = ZegoLiveStreamingLifecycle.claim();
    await ZegoLiveStreamingLifecycle.init(b, () async => log.add('initB'));

    expect(log, ['initA', 'disposeA', 'initB']);
  });

  test('adopt moves ownership for a session restored from minimize', () async {
    final a = ZegoLiveStreamingLifecycle.claim();
    await ZegoLiveStreamingLifecycle.init(a, () async {});

    final restored = ZegoLiveStreamingLifecycle.claim();
    await ZegoLiveStreamingLifecycle.adopt(restored);

    expect(ZegoLiveStreamingLifecycle.owns(restored), isTrue);
    expect(ZegoLiveStreamingLifecycle.owns(a), isFalse);

    await ZegoLiveStreamingLifecycle.dispose(a, () async {
      fail('stale teardown of the old token must not run');
    });
    expect(ZegoLiveStreamingLifecycle.owns(restored), isTrue);

    await ZegoLiveStreamingLifecycle.dispose(restored, () async {});
    expect(ZegoLiveStreamingLifecycle.owns(restored), isFalse);
  });
}