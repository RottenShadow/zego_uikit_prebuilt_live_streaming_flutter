part of 'services.dart';

/// Maximum time a single completer entry may remain uncompleted before the
/// safety timeout fires and drains every stuck entry in the queue.
///
/// This is a defence-in-depth mechanism: under normal operation
/// [completeCompleter] / [completeRoomAttributesCompleter] completes the
/// head entry immediately after the async work finishes.  The timer only
/// fires when an uncaught exception in the async body prevented the
/// [completeXxxCompleter] call from executing, which would otherwise leave
/// the queue permanently blocked.
const _kCompleterTimeout = Duration(seconds: 15);

extension PKServiceCompleter on ZegoUIKitPrebuiltLiveStreamingPKServices {
  /// Serializes [onPKUsersChanged] calls so at most one is in flight.
  ///
  /// Each caller adds a [Completer] to [_completerQueue] and awaits the
  /// previous entry's future.  [completeCompleter] removes and completes
  /// the head entry once the work is done.
  ///
  /// **Safety timeout:** If the head completer is still incomplete after
  /// [_kCompleterTimeout] (e.g. the handler threw before calling
  /// [completeCompleter]), the timer drains every stuck entry up to and
  /// including the current one, logging an error so the condition is
  /// visible in production logs.
  Future<void> waitCompleter(String apiName) async {
    final completer = Completer<void>();
    _completerQueue.add(completer);

    // Safety timeout: if the previous completer is stuck (e.g. an exception
    // prevented completeCompleter from running), auto-drain the queue so we
    // don't block forever.
    Timer(_kCompleterTimeout, () {
      if (!completer.isCompleted && _completerQueue.contains(completer)) {
        ZegoLoggerService.logError(
          '$apiName, waitCompleter TIMEOUT after ${_kCompleterTimeout.inSeconds}s '
          '(queue length: ${_completerQueue.length}), draining stuck entries',
          tag: 'live-streaming-pk',
          subTag: 'service',
        );
        // Complete every stuck completer up to and including this one so
        // that callers awaiting .future are unblocked.
        while (_completerQueue.isNotEmpty) {
          final stuck = _completerQueue.removeAt(0);
          if (!stuck.isCompleted) stuck.complete();
          if (stuck == completer) break;
        }
      }
    });

    if (_completerQueue.length > 1) {
      ZegoLoggerService.logInfo(
        '$apiName, waitCompleter start (queue length: ${_completerQueue.length})',
        tag: 'live-streaming-pk',
        subTag: 'service',
      );
      await _completerQueue[_completerQueue.length - 2].future;
      ZegoLoggerService.logInfo(
        '$apiName, waitCompleter done',
        tag: 'live-streaming-pk',
        subTag: 'service',
      );
    }
  }

  /// Completes the head entry of [_completerQueue], unblocking the next
  /// queued caller.
  void completeCompleter(String apiName) {
    ZegoLoggerService.logInfo(
      '$apiName, _completeCompleter',
      tag: 'live-streaming-pk',
      subTag: 'service',
    );
    if (_completerQueue.isNotEmpty) {
      final activeCompleter = _completerQueue.removeAt(0);
      if (!activeCompleter.isCompleted) {
        activeCompleter.complete();
      }
    }
  }

  /// Serializes room-attribute-driven PK updates so a delete (PK end) and
  /// a later re-set (PK restart) can never interleave.
  ///
  /// Mirrors [waitCompleter] but operates on [_roomAttributesCompleterQueue].
  /// The same safety-timeout mechanism applies: if the head entry is not
  /// completed within [_kCompleterTimeout], every stuck entry is drained
  /// and an error is logged.
  Future<void> waitRoomAttributesCompleter(String apiName) async {
    final completer = Completer<void>();
    _roomAttributesCompleterQueue.add(completer);

    // Safety timeout: if the previous completer is stuck (e.g. an exception
    // prevented completeRoomAttributesCompleter from running), auto-drain
    // the queue so we don't block forever.
    Timer(_kCompleterTimeout, () {
      if (!completer.isCompleted &&
          _roomAttributesCompleterQueue.contains(completer)) {
        ZegoLoggerService.logError(
          '$apiName, waitRoomAttributesCompleter TIMEOUT after '
          '${_kCompleterTimeout.inSeconds}s '
          '(queue length: ${_roomAttributesCompleterQueue.length}), '
          'draining stuck entries',
          tag: 'live-streaming-pk',
          subTag: 'service',
        );
        while (_roomAttributesCompleterQueue.isNotEmpty) {
          final stuck = _roomAttributesCompleterQueue.removeAt(0);
          if (!stuck.isCompleted) stuck.complete();
          if (stuck == completer) break;
        }
      }
    });

    if (_roomAttributesCompleterQueue.length > 1) {
      ZegoLoggerService.logInfo(
        '$apiName, waitRoomAttributesCompleter start (queue length: ${_roomAttributesCompleterQueue.length})',
        tag: 'live-streaming-pk',
        subTag: 'service',
      );
      await _roomAttributesCompleterQueue[_roomAttributesCompleterQueue.length - 2].future;
      ZegoLoggerService.logInfo(
        '$apiName, waitRoomAttributesCompleter done',
        tag: 'live-streaming-pk',
        subTag: 'service',
      );
    }
  }

  /// Completes the head entry of [_roomAttributesCompleterQueue],
  /// unblocking the next queued room-attribute handler.
  void completeRoomAttributesCompleter(String apiName) {
    ZegoLoggerService.logInfo(
      '$apiName, completeRoomAttributesCompleter',
      tag: 'live-streaming-pk',
      subTag: 'service',
    );
    if (_roomAttributesCompleterQueue.isNotEmpty) {
      final activeCompleter = _roomAttributesCompleterQueue.removeAt(0);
      if (!activeCompleter.isCompleted) {
        activeCompleter.complete();
      }
    }
  }
}
