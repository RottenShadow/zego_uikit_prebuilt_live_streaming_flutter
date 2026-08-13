// Flutter imports:
import 'package:flutter/widgets.dart';

// Package imports:
import 'package:zego_uikit/zego_uikit.dart';

/// Pinch-to-zoom the local camera from any audio/video surface (normal live,
/// PK battle, preview). The zoom factor is clamped between 1.0 and the
/// camera's maximum, and is applied at the capture level, so it is also seen
/// by viewers via the published/mixed stream.
mixin ZegoLiveStreamingCameraZoomMixin {
  double _cameraZoomFactor = 1.0;
  double _cameraZoomStartFactor = 1.0;
  double? _cameraMaxZoomFactor;

  Future<double> getMaxCameraZoomFactor() async {
    return _cameraMaxZoomFactor ??= await ZegoUIKit().getCameraMaxZoomFactor();
  }

  void onCameraScaleStart(ScaleStartDetails details) {
    _cameraZoomStartFactor = _cameraZoomFactor;
  }

  Future<void> onCameraScaleUpdate(ScaleUpdateDetails details) async {
    final maxFactor = await getMaxCameraZoomFactor();
    final factor = (_cameraZoomStartFactor * details.scale)
        .clamp(1.0, maxFactor)
        .toDouble();
    if (factor != _cameraZoomFactor) {
      _cameraZoomFactor = factor;
      await ZegoUIKit().setCameraZoomFactor(factor);
    }
  }

  Widget withCameraPinchZoom(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: onCameraScaleStart,
      onScaleUpdate: onCameraScaleUpdate,
      child: child,
    );
  }
}
