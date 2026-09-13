// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:zego_uikit/zego_uikit.dart';

// Project imports:
import 'package:zego_uikit_prebuilt_live_streaming/src/config/dialogs.dart';
import 'package:zego_uikit_prebuilt_live_streaming/src/components/utils/dialogs.dart';

/// Shows the background timeout dialog when the user returns to the app
/// after being in the background for the configured duration.
///
/// Returns `true` if the user chose to resume, `false` if they chose to leave.
Future<bool> showBackgroundTimeoutDialog({
  required BuildContext context,
  required bool rootNavigator,
  required ZegoLiveStreamingBackgroundTimeoutDialogConfig config,
}) async {
  if (config.dialogBuilder != null) {
    return _showCustomDialog(
      context: context,
      rootNavigator: rootNavigator,
      config: config,
    );
  }

  return _showDefaultDialog(
    context: context,
    rootNavigator: rootNavigator,
    config: config,
  );
}

Future<bool> _showCustomDialog({
  required BuildContext context,
  required bool rootNavigator,
  required ZegoLiveStreamingBackgroundTimeoutDialogConfig config,
}) async {
  var result = false;
  try {
    result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: rootNavigator,
      builder: (dialogContext) {
        return config.dialogBuilder!(
          dialogContext,
          () => Navigator.of(dialogContext, rootNavigator: rootNavigator).pop(true),
          () => Navigator.of(dialogContext, rootNavigator: rootNavigator).pop(false),
        );
      },
    ) ?? false;
  } catch (e) {
    ZegoLoggerService.logInfo(
      'show custom background timeout dialog exception:$e',
      tag: 'live-streaming',
      subTag: 'background_timeout_dialog',
    );
  }

  return result;
}

Future<bool> _showDefaultDialog({
  required BuildContext context,
  required bool rootNavigator,
  required ZegoLiveStreamingBackgroundTimeoutDialogConfig config,
}) async {
  return showLiveDialog(
    context: context,
    rootNavigator: rootNavigator,
    title: config.text.title,
    content: config.text.message,
    leftButtonText: config.text.leaveButton,
    leftButtonCallback: () {
      Navigator.of(
        context,
        rootNavigator: rootNavigator,
      ).pop(false);
    },
    rightButtonText: config.text.resumeButton,
    rightButtonCallback: () {
      Navigator.of(
        context,
        rootNavigator: rootNavigator,
      ).pop(true);
    },
  );
}
