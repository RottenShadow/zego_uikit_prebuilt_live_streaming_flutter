// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/cupertino.dart';

// Package imports:
import 'package:zego_uikit/zego_uikit.dart';

// Project imports:
import 'package:zego_uikit_prebuilt_live_streaming/src/config.dart';
import 'package:zego_uikit_prebuilt_live_streaming/src/events.dart';
import 'package:zego_uikit_prebuilt_live_streaming/src/events.defines.dart';
import 'package:zego_uikit_prebuilt_live_streaming/src/minimizing/overlay_machine.dart';

/// @nodoc
class ZegoLiveStreamingPlugins {
  ZegoLiveStreamingPlugins({
    required this.appID,
    required this.appSign,
    required this.token,
    required this.userID,
    required this.userName,
    required this.roomID,
    required this.plugins,
    required this.events,
    this.onPluginReLogin,
    this.onRoomLoginFailed,
    this.signalingPluginConfig,
    this.beautyConfig,
  }) {
    _install();
  }

  final int appID;
  final String appSign;
  final String token;

  final String userID;
  final String userName;

  final String roomID;

  final ZegoLiveStreamingSignalingPluginConfig? signalingPluginConfig;
  final ZegoBeautyPluginConfig? beautyConfig;

  final List<IZegoUIKitPlugin> plugins;

  final VoidCallback? onPluginReLogin;
  final ZegoLiveStreamingLoginFailedEvent? onRoomLoginFailed;

  final ZegoUIKitPrebuiltLiveStreamingEvents events;

  List<StreamSubscription<dynamic>?> subscriptions = [];
  ValueNotifier<ZegoSignalingPluginConnectionState> pluginUserStateNotifier =
      ValueNotifier<ZegoSignalingPluginConnectionState>(
          ZegoSignalingPluginConnectionState.disconnected);
  ValueNotifier<ZegoSignalingPluginRoomState> roomStateNotifier =
      ValueNotifier<ZegoSignalingPluginRoomState>(
          ZegoSignalingPluginRoomState.disconnected);
  bool tryReLogging = false;
  bool initialized = false;
  bool roomHasInitLogin = false;

  bool get isEnabled => plugins.isNotEmpty;

  void _install() {
    ZegoLoggerService.logInfo(
      'plugins:$plugins',
      tag: 'live-streaming-plugin',
      subTag: 'install',
    );

    ZegoUIKit().installPlugins(plugins);

    for (final pluginType in ZegoUIKitPluginType.values) {
      ZegoUIKit().getPlugin(pluginType)?.getVersion().then((version) {
        ZegoLoggerService.logInfo(
          'plugin-$pluginType version: $version installed',
          tag: 'live-streaming-plugin',
          subTag: 'plugin',
        );
      });
    }

    if (ZegoPluginAdapter().getPlugin(ZegoUIKitPluginType.signaling) != null) {
      subscriptions.add(ZegoUIKit()
          .getSignalingPlugin()
          .getErrorStream()
          .listen(onSignalingError));
    }

    if (ZegoPluginAdapter().getPlugin(ZegoUIKitPluginType.beauty) != null) {
      subscriptions
        ..add(ZegoUIKit()
            .getBeautyPlugin()
            .getErrorStream()
            .listen(onBeautyError))
        ..add(ZegoUIKit()
            .getBeautyPlugin()
            .getFaceDetectionEventStream()
            .listen(onFaceDetectionEvent));

      ZegoUIKit().enableCustomVideoProcessing(true);
    }
  }

  Future<void> init() async {
    if (initialized) {
      ZegoLoggerService.logInfo(
        'had init',
        tag: 'live-streaming-plugin',
        subTag: 'init',
      );

      return;
    }

    initialized = true;

    pluginUserStateNotifier.value =
        ZegoUIKit().getSignalingPlugin().getConnectionState();
    roomStateNotifier.value = ZegoUIKit().getSignalingPlugin().getRoomState();

    ZegoLoggerService.logInfo(
      'user state:${pluginUserStateNotifier.value}, '
      'room state:${roomStateNotifier.value}',
      tag: 'live-streaming-plugin',
      subTag: 'init',
    );

    await ZegoUIKit()
        .getSignalingPlugin()
        .init(appID, appSign: appSign)
        .then((value) {
      ZegoLoggerService.logInfo(
        'done',
        tag: 'live-streaming-plugin',
        subTag: 'init',
      );
    });

    subscriptions
      ..add(ZegoUIKit()
          .getSignalingPlugin()
          .getConnectionStateStream()
          .listen(onUserConnectionState))
      ..add(ZegoUIKit()
          .getSignalingPlugin()
          .getRoomStateStream()
          .listen(onRoomState));

    ZegoLoggerService.logInfo(
      'login...',
      tag: 'live-streaming-plugin',
      subTag: 'init',
    );
    await ZegoUIKit()
        .getSignalingPlugin()
        .login(
          id: userID,
          name: userName,
          token: token,
        )
        .then((result) async {
      ZegoLoggerService.logInfo(
        'login done, login result:$result, try to join room...',
        tag: 'live-streaming-plugin',
        subTag: 'init',
      );

      return joinRoom().then((bool success) {
        ZegoLoggerService.logInfo(
          'room joined, join success:$success',
          tag: 'live-streaming-plugin',
          subTag: 'init',
        );
        roomHasInitLogin = success;
      });
    });

    await initAdvanceEffectsPlugins();

    ZegoLoggerService.logInfo(
      'all done',
      tag: 'live-streaming-plugin',
      subTag: 'init',
    );
  }

  Future<bool> joinRoom() async {
    ZegoLoggerService.logInfo(
      'try join',
      tag: 'live-streaming-plugin',
      subTag: 'joinRoom',
    );

    return ZegoUIKit()
        .getSignalingPlugin()
        .joinRoom(
          roomID,
          force: true,
        )
        .then((result) {
      if (result.error != null) {
        onRoomLoginFailed?.call(-1, result.error.toString());

        ZegoLoggerService.logInfo(
          'failed: ${result.error}',
          tag: 'live-streaming-plugin',
          subTag: 'joinRoom',
        );
      } else {
        ZegoLoggerService.logInfo(
          'success',
          tag: 'live-streaming-plugin',
          subTag: 'joinRoom',
        );
      }

      return result.error == null;
    });
  }

  Future<void> initAdvanceEffectsPlugins() async {
    final useAdvanceEffect =
        ZegoPluginAdapter().getPlugin(ZegoUIKitPluginType.beauty) != null;

    if (!useAdvanceEffect) {
      return;
    }

    ZegoUIKit()
        .getBeautyPlugin()
        .setConfig(beautyConfig ?? ZegoBeautyPluginConfig());
    await ZegoUIKit().getBeautyPlugin().init(appID, appSign).then((value) {
      ZegoLoggerService.logInfo(
        'done',
        tag: 'live-streaming-plugin',
        subTag: 'initAdvanceEffectsPlugins',
      );
    });
  }

  Future<void> uninitAdvanceEffectsPlugins() async {
    if (ZegoPluginAdapter().getPlugin(ZegoUIKitPluginType.beauty) != null) {
      await ZegoUIKit().getBeautyPlugin().uninit();
    }

    ZegoUIKit().uninstallPlugins(
      plugins
          .where((e) => e.getPluginType() == ZegoUIKitPluginType.beauty)
          .toList(),
    );
  }

  Future<void> uninit() async {
    if (!initialized) {
      ZegoLoggerService.logInfo(
        'is not init before',
        tag: 'live-streaming-plugin',
        subTag: 'uninit',
      );
    }

    ZegoLoggerService.logInfo(
      '',
      tag: 'live-streaming-plugin',
      subTag: 'uninit',
    );
    initialized = false;

    roomHasInitLogin = false;
    tryReLogging = false;

    if (ZegoLiveStreamingMiniOverlayMachine().isMinimizing) {
      ZegoLoggerService.logInfo(
        'to minimizing, not need to leave room, logout and uninit',
        tag: 'live-streaming-plugin',
        subTag: 'uninit',
      );
    } else {
      if (ZegoPluginAdapter().getPlugin(ZegoUIKitPluginType.signaling) !=
          null) {
        if (signalingPluginConfig?.leaveRoomOnDispose ?? true) {
          await ZegoUIKit().getSignalingPlugin().leaveRoom();
        }

        /// not need logout
        // await ZegoUIKit().getSignalingPlugin().logout();
        /// not need destroy signaling sdk
        ///
        if (signalingPluginConfig?.uninitOnDispose ?? true) {
          await ZegoUIKit().getSignalingPlugin().uninit(forceDestroy: false);

          ZegoUIKit().uninstallPlugins(
            plugins
                .where(
                    (e) => e.getPluginType() == ZegoUIKitPluginType.signaling)
                .toList(),
          );
        }
      }
    }

    uninitAdvanceEffectsPlugins();

    for (final streamSubscription in subscriptions) {
      streamSubscription?.cancel();
    }
  }

  Future<void> onUserInfoUpdate(String userID, String userName) async {
    final localUser = ZegoUIKit().getLocalUser();

    ZegoLoggerService.logInfo(
      'target user($userID, $userName), '
      'local user:($localUser) '
      'initialized:$initialized, '
      'user state:${pluginUserStateNotifier.value}'
      'room state:${roomStateNotifier.value}',
      tag: 'live-streaming-plugin',
      subTag: 'onUserInfoUpdate',
    );

    if (!initialized) {
      ZegoLoggerService.logInfo(
        ', plugin is not init',
        tag: 'live-streaming-plugin',
        subTag: 'onUserInfoUpdate',
      );
      return;
    }

    if (pluginUserStateNotifier.value !=
        ZegoSignalingPluginConnectionState.connected) {
      ZegoLoggerService.logInfo(
        ', user state is not connected',
        tag: 'live-streaming-plugin',
        subTag: 'onUserInfoUpdate',
      );
      return;
    }

    if (ZegoSignalingPluginRoomState.connected != roomStateNotifier.value) {
      ZegoLoggerService.logInfo(
        ', room state is not connected',
        tag: 'live-streaming-plugin',
        subTag: 'onUserInfoUpdate',
      );
      return;
    }

    if (localUser.id == userID && localUser.name == userName) {
      ZegoLoggerService.logInfo(
        'same user, cancel this re-login',
        tag: 'live-streaming-plugin',
        subTag: 'onUserInfoUpdate',
      );
      return;
    }

    await ZegoUIKit().getSignalingPlugin().logout();
    await ZegoUIKit().getSignalingPlugin().login(
          id: userID,
          name: userName,
          token: token,
        );
  }

  void onUserConnectionState(
      ZegoSignalingPluginConnectionStateChangedEvent event) {
    ZegoLoggerService.logInfo(
      ', param: $event',
      tag: 'live-streaming-plugin',
      subTag: 'onUserConnectionState',
    );

    pluginUserStateNotifier.value = event.state;

    ZegoLoggerService.logInfo(
      ', user state: ${pluginUserStateNotifier.value}',
      tag: 'live-streaming-plugin',
      subTag: 'onUserConnectionState',
    );

    if (tryReLogging &&
        pluginUserStateNotifier.value ==
            ZegoSignalingPluginConnectionState.connected) {
      tryReLogging = false;
      onPluginReLogin?.call();
    }

    tryReEnterRoom();
  }

  void onRoomState(ZegoSignalingPluginRoomStateChangedEvent event) {
    ZegoLoggerService.logInfo(
      ', event: $event',
      tag: 'live-streaming-plugin',
      subTag: 'onRoomState',
    );

    roomStateNotifier.value = event.state;

    ZegoLoggerService.logInfo(
      ', state: ${roomStateNotifier.value}, '
      'networkState:${ZegoUIKit().getNetworkModeStream()}',
      tag: 'live-streaming-plugin',
      subTag: 'onRoomState',
    );

    tryReEnterRoom();
  }

  void onSignalingError(ZegoSignalingError error) {
    ZegoLoggerService.logError(
      'on signaling error:$error',
      tag: 'live-streaming-plugin',
      subTag: 'plugin',
    );

    events.onError?.call(ZegoUIKitError(
      code: error.code,
      message: error.message,
      method: error.method,
    ));
  }

  void onFaceDetectionEvent(ZegoBeautyPluginFaceDetectionData data) {
    events.beauty.onFaceDetection?.call(data);
  }

  void onBeautyError(ZegoBeautyError error) {
    ZegoLoggerService.logError(
      'on beauty error:$error',
      tag: 'live-streaming-plugin',
      subTag: 'prebuilt',
    );

    events.beauty.onError?.call(error);
  }

  Future<void> tryReLogin({String? updatedToken}) async {
    ZegoLoggerService.logInfo(
      'state:${pluginUserStateNotifier.value}',
      tag: 'live-streaming-plugin',
      subTag: 'plugin',
    );

    if (!initialized) {
      ZegoLoggerService.logInfo(
        'plugin is not init',
        tag: 'live-streaming-plugin',
        subTag: 'tryReLogin',
      );
      return;
    }

    if (pluginUserStateNotifier.value !=
        ZegoSignalingPluginConnectionState.disconnected) {
      ZegoLoggerService.logInfo(
        'user state is not disconnected',
        tag: 'live-streaming-plugin',
        subTag: 'tryReLogin',
      );
      return;
    }

    final loginToken = updatedToken ?? token;

    ZegoLoggerService.logInfo(
      'id:$userID, name:$userName, hasToken:${loginToken.isNotEmpty}',
      tag: 'live-streaming-plugin',
      subTag: 'tryReLogin',
    );
    tryReLogging = true;
    return ZegoUIKit().getSignalingPlugin().logout().then((value) async {
      await ZegoUIKit().getSignalingPlugin().login(
            id: userID,
            name: userName,
            token: loginToken,
          );
    });
  }

  Future<bool> tryReEnterRoom() async {
    ZegoLoggerService.logInfo(
      ', room state: ${roomStateNotifier.value}, networkState:${ZegoUIKit().getNetworkState()}',
      tag: 'live-streaming-plugin',
      subTag: 'tryReEnterRoom',
    );

    if (!initialized) {
      ZegoLoggerService.logInfo(
        ', plugin is not init',
        tag: 'live-streaming-plugin',
        subTag: 'tryReEnterRoom',
      );
      return false;
    }
    if (!roomHasInitLogin) {
      ZegoLoggerService.logInfo(
        ', first login room has not finished',
        tag: 'live-streaming-plugin',
        subTag: 'tryReEnterRoom',
      );
      return false;
    }

    if (ZegoSignalingPluginRoomState.disconnected != roomStateNotifier.value) {
      ZegoLoggerService.logInfo(
        ', room state is not disconnected',
        tag: 'live-streaming-plugin',
        subTag: 'tryReEnterRoom',
      );
      return false;
    }

    if (ZegoUIKit().getNetworkState() != ZegoUIKitNetworkState.online) {
      ZegoLoggerService.logInfo(
        ', network is not connected',
        tag: 'live-streaming-plugin',
        subTag: 'tryReEnterRoom',
      );
      return false;
    }

    if (pluginUserStateNotifier.value !=
        ZegoSignalingPluginConnectionState.connected) {
      ZegoLoggerService.logInfo(
        ', user state is not connected',
        tag: 'live-streaming-plugin',
        subTag: 'tryReEnterRoom',
      );
      return false;
    }

    ZegoLoggerService.logInfo(
      'try join',
      tag: 'live-streaming-plugin',
      subTag: 'tryReEnterRoom',
    );
    return joinRoom().then((result) {
      ZegoLoggerService.logInfo(
        'result:$result',
        tag: 'live-streaming-plugin',
        subTag: 'tryReEnterRoom',
      );

      if (!result) {
        return false;
      }

      onPluginReLogin?.call();

      return true;
    });
  }

  /// Waits for the signaling connection state to leave [ZegoSignalingPluginConnectionState.reconnecting].
  /// ZIM login() hangs if called while the SDK is reconnecting, so we must
  /// wait for it to settle into either [ZegoSignalingPluginConnectionState.connected]
  /// or [ZegoSignalingPluginConnectionState.disconnected] before proceeding.
  Future<void> _waitForReconnectingSettled({Duration timeout = const Duration(seconds: 5)}) async {
    final currentState = ZegoUIKit().getSignalingPlugin().getConnectionState();
    if (currentState != ZegoSignalingPluginConnectionState.reconnecting) {
      return;
    }

    ZegoLoggerService.logInfo(
      'signaling is reconnecting, waiting for it to settle...',
      tag: 'live-streaming-plugin',
      subTag: 'reconnectAll',
    );

    final completer = Completer<void>();
    final timer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      final state = ZegoUIKit().getSignalingPlugin().getConnectionState();
      if (state != ZegoSignalingPluginConnectionState.reconnecting) {
        if (timer.isActive) timer.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });

    Future.delayed(timeout, () {
      if (timer.isActive) timer.cancel();
      if (!completer.isCompleted) {
        ZegoLoggerService.logInfo(
          'wait for reconnecting settled timed out, proceeding anyway',
          tag: 'live-streaming-plugin',
          subTag: 'reconnectAll',
        );
        completer.complete();
      }
    });

    return completer.future;
  }

  /// Checks all connection states (Express engine, Express room, Signaling user,
  /// Signaling room) and attempts to reconnect any that are disconnected.
  ///
  /// Retries up to [maxRetries] times with 1-second delay between attempts.
  /// Returns `true` if all states are OK after reconnection, `false` if all
  /// retries failed.
  Future<bool> reconnectAll({
    required String token,
    bool markAsLargeRoom = false,
    int maxRetries = 3,
  }) async {
    if (!initialized) {
      ZegoLoggerService.logInfo(
        'plugin is not init, skip reconnectAll',
        tag: 'live-streaming-plugin',
        subTag: 'reconnectAll',
      );
      return false;
    }

    for (var i = 0; i < maxRetries; i++) {
      final expressRoomOk = ZegoUIKit().isRoomLogin;
      final signalingUserOk =
          ZegoUIKit().getSignalingPlugin().getConnectionState() ==
              ZegoSignalingPluginConnectionState.connected;
      final signalingRoomOk = ZegoUIKit().getSignalingPlugin().getRoomState() ==
          ZegoSignalingPluginRoomState.connected;

      ZegoLoggerService.logInfo(
        'reconnectAll attempt ${i + 1}/$maxRetries: '
        'expressRoom:$expressRoomOk, '
        'signalingUser:$signalingUserOk, signalingRoom:$signalingRoomOk',
        tag: 'live-streaming-plugin',
        subTag: 'reconnectAll',
      );

      if (expressRoomOk && signalingUserOk && signalingRoomOk) {
        return true;
      }

      // Fix signaling user login if disconnected
      if (!signalingUserOk) {
        // ZIM login() hangs if called while SDK is reconnecting — wait for it to settle
        await _waitForReconnectingSettled();
        try {
          await ZegoUIKit().getSignalingPlugin().logout();
          await ZegoUIKit().getSignalingPlugin().login(
                id: userID,
                name: userName,
                token: token,
              );
          ZegoLoggerService.logInfo(
            'signaling user re-login done',
            tag: 'live-streaming-plugin',
            subTag: 'reconnectAll',
          );
        } catch (e) {
          ZegoLoggerService.logError(
            'signaling user re-login failed: $e',
            tag: 'live-streaming-plugin',
            subTag: 'reconnectAll',
          );
        }
      }

      // Fix signaling room if not connected
      if (!signalingRoomOk) {
        try {
          await ZegoUIKit().getSignalingPlugin().joinRoom(roomID);
          ZegoLoggerService.logInfo(
            'signaling room re-join done',
            tag: 'live-streaming-plugin',
            subTag: 'reconnectAll',
          );
        } catch (e) {
          ZegoLoggerService.logError(
            'signaling room re-join failed: $e',
            tag: 'live-streaming-plugin',
            subTag: 'reconnectAll',
          );
        }
      }

      // Fix Express room if not logged in
      if (!expressRoomOk) {
        try {
          await ZegoUIKit().joinRoom(
            roomID,
            token: token,
            markAsLargeRoom: markAsLargeRoom,
          );
          ZegoLoggerService.logInfo(
            'express room re-join done',
            tag: 'live-streaming-plugin',
            subTag: 'reconnectAll',
          );
        } catch (e) {
          ZegoLoggerService.logError(
            'express room re-join failed: $e',
            tag: 'live-streaming-plugin',
            subTag: 'reconnectAll',
          );
        }
      }

      if (i < maxRetries - 1) {
        await Future.delayed(const Duration(seconds: 5));
      }
    }

    ZegoLoggerService.logError(
      'reconnectAll failed after $maxRetries retries',
      tag: 'live-streaming-plugin',
      subTag: 'reconnectAll',
    );

    return false;
  }
}
