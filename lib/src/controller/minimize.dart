part of 'package:zego_uikit_prebuilt_live_streaming/src/controller.dart';

mixin ZegoLiveStreamingControllerMinimizing {
  final _minimizingImpl = ZegoLiveStreamingControllerMinimizingImpl();

  ZegoLiveStreamingControllerMinimizingImpl get minimize => _minimizingImpl;
}

/// Here are the APIs related to screen sharing.
class ZegoLiveStreamingControllerMinimizingImpl
    with ZegoLiveStreamingControllerMinimizingPrivate {
  /// current minimize state
  ZegoLiveStreamingMiniOverlayPageState get state =>
      ZegoLiveStreamingMiniOverlayMachine().state;

  /// Is it currently in the minimized state or not
  bool get isMinimizing => isMinimizingNotifier.value;
  ValueNotifier<bool> get isMinimizingNotifier => _private.isMinimizingNotifier;

  /// restore the [ZegoUIKitPrebuiltLiveStreaming] from minimize
  bool restore(
    BuildContext context, {
    bool rootNavigator = true,
    bool withSafeArea = false,
  }) {
    if (ZegoLiveStreamingMiniOverlayPageState.minimizing != state) {
      ZegoLoggerService.logInfo(
        'is not minimizing, ignore',
        tag: 'live-streaming',
        subTag: 'controller.minimize, restore',
      );

      return false;
    }

    final minimizeData = private.minimizeData;
    if (null == minimizeData) {
      ZegoLoggerService.logError(
        'prebuiltData is null',
        tag: 'live-streaming',
        subTag: 'controller.minimize, restore',
      );

      return false;
    }

    /// re-enter prebuilt live streaming
    ZegoLiveStreamingMiniOverlayMachine().changeState(
      ZegoLiveStreamingMiniOverlayPageState.living,
    );

    try {
      Navigator.of(
        context,
        rootNavigator: true,
      ).push(
        MaterialPageRoute(builder: (context) {
          final isSwiping = minimizeData.config.swiping != null;
          final prebuiltLiveStreaming = ZegoUIKitPrebuiltLiveStreaming(
            appID: minimizeData.appID,
            appSign: minimizeData.appSign,
            userID: minimizeData.userID,
            userName: minimizeData.userName,
            liveID: isSwiping
                ? ZegoUIKitPrebuiltLiveStreamingController()
                    .swiping
                    .private
                    .currentSwipingID
                : minimizeData.liveID,
            config: minimizeData.config,
            events: minimizeData.events,
          );
          return withSafeArea
              ? SafeArea(
                  child: prebuiltLiveStreaming,
                )
              : prebuiltLiveStreaming;
        }),
      );
    } catch (e) {
      ZegoLoggerService.logInfo(
        'restore from mini exception:$e',
        tag: 'live-streaming',
        subTag: 'controller.minimize, restore',
      );
    }

    return true;
  }

  /// To minimize the [ZegoUIKitPrebuiltLiveStreaming]
  bool minimize(
    BuildContext context, {
    bool rootNavigator = true,
  }) {
    if (ZegoLiveStreamingMiniOverlayMachine().isMinimizing) {
      ZegoLoggerService.logInfo(
        'is minimizing, ignore',
        tag: 'live-streaming',
        subTag: 'controller.minimize, minimize',
      );

      return false;
    }

    if (!private.isLiving) {
      ZegoLoggerService.logInfo(
        'is not living, ignore',
        tag: 'live-streaming',
        subTag: 'controller.minimize, minimize',
      );

      return false;
    }

    ZegoLiveStreamingMiniOverlayMachine().changeState(
      ZegoLiveStreamingMiniOverlayPageState.minimizing,
    );

    try {
      /// pop live streaming page
      Navigator.of(
        context,
        rootNavigator: rootNavigator,
      ).pop();
    } catch (e) {
      ZegoLoggerService.logError(
        'navigator pop exception:$e',
        tag: 'live-streaming',
        subTag: 'controller.minimize, minimize',
      );

      return false;
    }

    return true;
  }

  /// if live streaming ended in minimizing state, not need to navigate, just
  /// hide the minimize widget.
  void hide() {
    ZegoLiveStreamingMiniOverlayMachine().changeState(
      ZegoLiveStreamingMiniOverlayPageState.idle,
    );
  }

  /// Force close the live streaming while it is minimized.
  ///
  /// It hides the minimize overlay and fully un-initializes the live
  /// streaming (leaves the room and stops the internal managers), without
  /// any page navigation, so it can be called without a [BuildContext].
  ///
  /// Returns `false` if the live streaming is not in the minimized state.
  Future<bool> forceClose() async {
    if (ZegoLiveStreamingMiniOverlayPageState.minimizing != state) {
      ZegoLoggerService.logInfo(
        'is not minimizing, ignore',
        tag: 'live-streaming',
        subTag: 'controller.minimize, force close',
      );

      return false;
    }

    final events = private.minimizeData?.events;

    /// hide the minimize overlay
    ZegoLiveStreamingMiniOverlayMachine().changeState(
      ZegoLiveStreamingMiniOverlayPageState.idle,
    );

    final hostManager = ZegoLiveStreamingManagers().hostManager;
    if (hostManager?.isLocalHost ?? false) {
      hostManager?.hostUpdateEnabledNotifier.value = false;
      await ZegoUIKit().updateRoomProperties({
        RoomPropertyKey.host.text: '',
        RoomPropertyKey.liveStatus.text: LiveStatus.ended.index.toString()
      });
    }

    await ZegoLiveStreamingManagers().uninitPluginAndManagers();
    await ZegoUIKit().resetSoundEffect();
    await ZegoUIKit().resetBeautyEffect();
    await ZegoUIKit().leaveRoom();

    await ZegoUIKitPrebuiltLiveStreamingController().pip.cancelBackground();

    events?.onEnded?.call(
      ZegoLiveStreamingEndEvent(
        reason: ZegoLiveStreamingEndReason.localLeave,
        isFromMinimizing: true,
      ),
      () {
        ZegoUIKitPrebuiltLiveStreamingController().minimize.hide();
      },
    );

    ZegoUIKitPrebuiltLiveStreamingController().private.uninitByPrebuilt();
    ZegoUIKitPrebuiltLiveStreamingController().pk.private.uninitByPrebuilt();
    ZegoUIKitPrebuiltLiveStreamingController().room.private.uninitByPrebuilt();
    ZegoUIKitPrebuiltLiveStreamingController()
        .user
        .private
        .uninitByPrebuilt();
    ZegoUIKitPrebuiltLiveStreamingController()
        .message
        .private
        .uninitByPrebuilt();
    ZegoUIKitPrebuiltLiveStreamingController()
        .coHost
        .private
        .uninitByPrebuilt();
    ZegoUIKitPrebuiltLiveStreamingController()
        .audioVideo
        .private
        .uninitByPrebuilt();
    ZegoUIKitPrebuiltLiveStreamingController()
        .minimize
        .private
        .uninitByPrebuilt();
    ZegoUIKitPrebuiltLiveStreamingController().pip.private.uninitByPrebuilt();
    ZegoUIKitPrebuiltLiveStreamingController()
        .screenSharing
        .private
        .uninitByPrebuilt();
    ZegoUIKitPrebuiltLiveStreamingController()
        .swiping
        .private
        .uninitByPrebuilt();

    return true;
  }
}
