// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:zego_express_engine/zego_express_engine.dart';
import 'package:zego_uikit/zego_uikit.dart';

// Project imports:
import 'package:zego_uikit_prebuilt_live_streaming/src/components/camera_zoom.dart';
import 'package:zego_uikit_prebuilt_live_streaming/src/config.dart';
import 'package:zego_uikit_prebuilt_live_streaming/src/pk/components/common.dart';
import 'package:zego_uikit_prebuilt_live_streaming/src/pk/core/defines.dart';
import 'package:zego_uikit_prebuilt_live_streaming/src/pk/layout/layout.dart';

class ZegoLiveStreamingPKHostView extends StatefulWidget {
  const ZegoLiveStreamingPKHostView({
    super.key,
    required this.hosts,
    required this.mixerLayout,
    required this.config,
    this.foregroundBuilder,
    this.backgroundBuilder,
    this.avatarConfig,
  });

  final ZegoLiveStreamingPKMixerLayout mixerLayout;
  final List<ZegoLiveStreamingPKUser> hosts;

  final ZegoUIKitPrebuiltLiveStreamingConfig config;
  final ZegoAudioVideoViewForegroundBuilder? foregroundBuilder;
  final ZegoAudioVideoViewBackgroundBuilder? backgroundBuilder;
  final ZegoAvatarConfig? avatarConfig;

  @override
  State<ZegoLiveStreamingPKHostView> createState() =>
      ZegoLiveStreamingPKHostViewState();
}

class ZegoLiveStreamingPKHostViewState
    extends State<ZegoLiveStreamingPKHostView>
    with ZegoLiveStreamingCameraZoomMixin {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final mixerLayoutResolution = widget.mixerLayout.getResolution();
      final rectList = widget.mixerLayout.getRectList(
        widget.hosts.length,
        scale: constraints.maxWidth / mixerLayoutResolution.width,
      );

      final separatorConfig = widget.config.pkBattle;

      return withCameraPinchZoom(
        Stack(
          children: [
            if (separatorConfig.separatorWidth > 0)
              Positioned.fill(
                child: ColoredBox(color: separatorConfig.separatorColor),
              ),
            ...hostAudioVideoViews(rectList, constraints),
            ...separatorViews(rectList),
          ],
        ),
      );
    });
  }

  List<Widget> separatorViews(List<Rect> rectList) {
    final separatorConfig = widget.config.pkBattle;
    if (separatorConfig.separatorWidth <= 0) return const [];

    return separatorRects(
      rectList,
      thickness: separatorConfig.separatorWidth,
      length: separatorConfig.separatorHeight,
    )
        .map(
          (rect) => Positioned.fromRect(
            rect: rect,
            child: ColoredBox(color: separatorConfig.separatorColor),
          ),
        )
        .toList();
  }

  List<Widget> hostAudioVideoViews(
    List<Rect> rectList,
    BoxConstraints constraints,
  ) {
    assert(rectList.length == widget.hosts.length);

    List<Widget> widgets = [];
    for (int idx = 0; idx < rectList.length; ++idx) {
      final rect = rectList[idx];
      final host = widget.hosts[idx];

      widgets.add(
        Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: ZegoAudioVideoView(
                user: host.userInfo,
                videoViewMode: ZegoViewMode.AspectFill,
                foregroundBuilder: (
                  BuildContext context,
                  Size size,
                  ZegoUIKitUser? user,
                  Map<String, dynamic> extraInfo,
                ) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: host.heartbeatBrokenNotifier,
                    builder: (context, isHeartbeatBroken, _) {
                      final updatedUser =
                          ZegoUIKit().getUserInMixerStream(host.userInfo.id);
                      return isHeartbeatBroken
                          ? Stack(
                              children: [
                                Container(
                                  color: Colors.black,
                                ),
                                widget.config.audioVideoView.foregroundBuilder
                                        ?.call(
                                      context,
                                      size,
                                      user,
                                      extraInfo,
                                    ) ??
                                    Container(color: Colors.transparent),
                                Center(
                                  child: widget.config.pkBattle
                                          .hostReconnectingBuilder
                                          ?.call(
                                        context,
                                        updatedUser,
                                        {},
                                      ) ??
                                      const CircularProgressIndicator(),
                                ),
                              ],
                            )
                          : widget.config.audioVideoView.foregroundBuilder
                                  ?.call(
                                context,
                                size,
                                user,
                                extraInfo,
                              ) ??
                              Container(color: Colors.transparent);
                    },
                  );
                },
                backgroundBuilder:
                    widget.config.audioVideoView.backgroundBuilder ??
                        defaultPKBackgroundBuilder,
                avatarConfig: avatarConfigFor(rect),
              ),
            ),
          ],
        ),
      );
    }

    return widgets;
  }

  ZegoAvatarConfig avatarConfigFor(Rect rect) {
    final userConfig = widget.avatarConfig;
    final avatarSize = userConfig?.size ?? Size(rect.width / 2, rect.width / 2);

    return ZegoAvatarConfig(
      showInAudioMode: userConfig?.showInAudioMode ??
          widget.config.audioVideoView.showAvatarInAudioMode,
      showSoundWavesInAudioMode: userConfig?.showSoundWavesInAudioMode ??
          widget.config.audioVideoView.showSoundWavesInAudioMode,
      verticalAlignment:
          userConfig?.verticalAlignment ?? ZegoAvatarAlignment.center,
      size: avatarSize,
      soundWaveColor: userConfig?.soundWaveColor,
      builder: userConfig?.builder ?? widget.config.avatarBuilder,
    );
  }
}
