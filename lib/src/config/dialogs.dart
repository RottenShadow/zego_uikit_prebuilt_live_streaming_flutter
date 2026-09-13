// Flutter imports:
import 'package:flutter/material.dart';

/// Container for all dialog configs in the live streaming package.
///
/// Add new dialog types as properties here for easy expansion.
///
/// Example:
///
/// ```dart
/// config..dialogs = ZegoLiveStreamingDialogsConfig(
///   backgroundTimeout: ZegoLiveStreamingBackgroundTimeoutDialogConfig(
///     timeout: Duration(seconds: 30),
///     dialogBuilder: (context, onResume, onLeave) {
///       return CustomAlertDialog(
///         title: 'Stream Paused',
///         content: "You've been away for a while",
///         actions: [
///           CustomDialogAction(text: 'Leave', onPressed: onLeave),
///           CustomDialogAction(text: 'Resume', onPressed: onResume),
///         ],
///       );
///     },
///   ),
/// );
/// ```
class ZegoLiveStreamingDialogsConfig {
  /// Background timeout dialog configuration.
  ///
  /// When the user puts the app in background for [ZegoLiveStreamingBackgroundTimeoutDialogConfig.timeout]
  /// duration, a dialog will be shown on resume with options to resume or leave the stream.
  ZegoLiveStreamingBackgroundTimeoutDialogConfig backgroundTimeout;

  ZegoLiveStreamingDialogsConfig({
    ZegoLiveStreamingBackgroundTimeoutDialogConfig? backgroundTimeout,
  }) : backgroundTimeout = backgroundTimeout ??
            ZegoLiveStreamingBackgroundTimeoutDialogConfig();

  @override
  String toString() {
    return 'ZegoLiveStreamingDialogsConfig:{'
        'backgroundTimeout:$backgroundTimeout, '
        '}';
  }
}

/// Configuration for the background timeout dialog.
///
/// This dialog appears when the user returns to the app after being in the
/// background for a specified duration. It provides options to resume or leave
/// the stream.
class ZegoLiveStreamingBackgroundTimeoutDialogConfig {
  /// Duration in background before showing dialog on resume.
  ///
  /// Default value is 30 seconds.
  Duration timeout;

  /// Default resume action.
  ///
  /// Checks Express engine state, Express room login, Signaling user connection,
  /// and Signaling room state. Retries up to 3 times with 1-second delay.
  /// Returns `true` if all checks pass, `false` if all retries fail.
  ///
  /// Volt can wrap this to add custom pre/post logic.
  Future<bool> Function()? onResume;

  /// Default leave action.
  ///
  /// Pops the live streaming screen.
  /// Volt can wrap this to add custom pre/post logic.
  VoidCallback? onLeave;

  /// Custom dialog builder.
  ///
  /// Receives [context], [onResume] and [onLeave] callbacks.
  /// Volt overrides this to use its own dialog style (e.g., CustomAlertDialog).
  ///
  /// If null, the default dialog will be shown.
  Widget Function(
    BuildContext context,
    VoidCallback onResume,
    VoidCallback onLeave,
  )? dialogBuilder;

  /// Dialog text strings.
  ///
  /// Volt can override these to provide localized text.
  ZegoLiveStreamingBackgroundTimeoutDialogText text;

  ZegoLiveStreamingBackgroundTimeoutDialogConfig({
    this.timeout = const Duration(seconds: 30),
    this.onResume,
    this.onLeave,
    this.dialogBuilder,
    ZegoLiveStreamingBackgroundTimeoutDialogText? text,
  }) : text = text ?? ZegoLiveStreamingBackgroundTimeoutDialogText();

  @override
  String toString() {
    return 'ZegoLiveStreamingBackgroundTimeoutDialogConfig:{'
        'timeout:$timeout, '
        'onResume:${onResume != null}, '
        'onLeave:${onLeave != null}, '
        'dialogBuilder:${dialogBuilder != null}, '
        'text:$text, '
        '}';
  }
}

/// Text strings for the background timeout dialog.
class ZegoLiveStreamingBackgroundTimeoutDialogText {
  /// Title of the dialog. Default: "Stream Paused".
  String title;

  /// Message content of the dialog. Default: "You've been away for a while. Do you want to resume?".
  String message;

  /// Text for the resume button. Default: "Resume Stream".
  String resumeButton;

  /// Text for the leave button. Default: "Leave Stream".
  String leaveButton;

  ZegoLiveStreamingBackgroundTimeoutDialogText({
    this.title = 'Stream Paused',
    this.message = "You've been away for a while. Do you want to resume?",
    this.resumeButton = 'Resume Stream',
    this.leaveButton = 'Leave Stream',
  });

  @override
  String toString() {
    return 'ZegoLiveStreamingBackgroundTimeoutDialogText:{'
        'title:$title, '
        'message:$message, '
        'resumeButton:$resumeButton, '
        'leaveButton:$leaveButton, '
        '}';
  }
}
