// Dart imports:
import 'dart:math' as math;

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Project imports:
import 'package:zego_uikit_prebuilt_live_streaming/src/pk/layout/prefer_gird_layout.dart';

/// width of mixer canvas
const zegoLiveStreamingPKMixerCanvasWidth = 810.0;

/// height of mixer canvas
const zegoLiveStreamingPKMixerCanvasHeight = 720.0;

/// Inheritance of the hybrid layout parent class allows you to return your
/// custom coordinates and modify the layout of the mixed stream.
/// You can refer to [ZegoLiveStreamingPKPreferGridMixerLayout] or [ZegoPKV2GridMixerLayout].
abstract class ZegoLiveStreamingPKMixerLayout {
  /// The size of the mixed stream canvas.
  /// default is zegoPK2MixerCanvasWidth x zegoPK2MixerCanvasHeight
  Size getResolution() {
    return const Size(
      zegoLiveStreamingPKMixerCanvasWidth,
      zegoLiveStreamingPKMixerCanvasHeight,
    );
  }

  /// Get the coordinates of the user's video frame on the PK layout at position [hostCount].
  List<Rect> getRectList(
    int hostCount, {
    double scale = 1.0,
  });
}

typedef ZegoLiveStreamingPKMixerDefaultLayout
    = ZegoLiveStreamingPKPreferGridMixerLayout;

const _separatorEdgeEpsilon = 1e-6;

bool _overlapsY(Rect a, Rect b) =>
    math.max(a.top, b.top) < math.min(a.bottom, b.bottom);

bool _overlapsX(Rect a, Rect b) =>
    math.max(a.left, b.left) < math.min(a.right, b.right);

/// Returns a line Rect centered on every edge shared by two adjacent cells in
/// [rects], so the separator adapts to any host count/grid. A vertical shared
/// edge yields a vertical line of [thickness] width; a horizontal shared edge
/// yields a horizontal line of [thickness] height. [length] is the line length
/// along the shared edge; a value <= 0 spans the whole shared edge.
List<Rect> separatorRects(
  List<Rect> rects, {
  required double thickness,
  double length = 0,
}) {
  if (thickness <= 0) return const [];

  final lines = <Rect>[];
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      final a = rects[i];
      final b = rects[j];

      if ((a.right - b.left).abs() <= _separatorEdgeEpsilon) {
        if (!_overlapsY(a, b)) continue;
        final top = math.max(a.top, b.top);
        final bottom = math.min(a.bottom, b.bottom);
        final lineHeight =
            length > 0 ? math.min(length, bottom - top) : bottom - top;
        final centerY = (top + bottom) / 2;
        lines.add(
          Rect.fromLTRB(
            a.right - thickness / 2,
            centerY - lineHeight / 2,
            a.right + thickness / 2,
            centerY + lineHeight / 2,
          ),
        );
      } else if ((a.bottom - b.top).abs() <= _separatorEdgeEpsilon) {
        if (!_overlapsX(a, b)) continue;
        final left = math.max(a.left, b.left);
        final right = math.min(a.right, b.right);
        final lineWidth =
            length > 0 ? math.min(length, right - left) : right - left;
        final centerX = (left + right) / 2;
        lines.add(
          Rect.fromLTRB(
            centerX - lineWidth / 2,
            a.bottom - thickness / 2,
            centerX + lineWidth / 2,
            a.bottom + thickness / 2,
          ),
        );
      }
    }
  }
  return lines;
}

/// Insets each rect in [rects] by [gap]/2 on every edge it shares with another
/// cell, leaving a [gap]-wide gutter between adjacent cells. Used to bake the
/// separator into the mixed stream.
List<Rect> insetSharedEdges(List<Rect> rects, double gap) {
  if (gap <= 0) return List.from(rects);

  return rects.map((r) {
    var left = r.left;
    var top = r.top;
    var right = r.right;
    var bottom = r.bottom;
    for (final other in rects) {
      if (identical(other, r)) continue;
      if ((other.right - r.left).abs() <= _separatorEdgeEpsilon &&
          _overlapsY(other, r)) {
        left += gap / 2;
      } else if ((other.left - r.right).abs() <= _separatorEdgeEpsilon &&
          _overlapsY(other, r)) {
        right -= gap / 2;
      }
      if ((other.bottom - r.top).abs() <= _separatorEdgeEpsilon &&
          _overlapsX(other, r)) {
        top += gap / 2;
      } else if ((other.top - r.bottom).abs() <= _separatorEdgeEpsilon &&
          _overlapsX(other, r)) {
        bottom -= gap / 2;
      }
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }).toList();
}
